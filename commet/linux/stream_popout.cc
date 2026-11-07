#include "stream_popout.h"

#include <gdk/gdkkeysyms.h>

#include <cstring>
#include <map>
#include <memory>

namespace {

FlEngine* g_engine = nullptr;
GtkWindow* g_main_window = nullptr;
FlMethodChannel* g_channel = nullptr;
bool g_shutting_down = false;

struct Popout {
  GtkWindow* window;
  int64_t view_id;
  int64_t request_id;
  bool fullscreen = false;
};
std::map<int64_t, std::unique_ptr<Popout>> g_windows;

void notify_view(const char* method, const Popout* entry) {
  g_autoptr(FlValue) args = fl_value_new_map();
  fl_value_set_string_take(args, "viewId", fl_value_new_int(entry->view_id));
  fl_value_set_string_take(args, "requestId", fl_value_new_int(entry->request_id));
  fl_value_set_string_take(args, "fullscreen", fl_value_new_bool(entry->fullscreen));
  fl_method_channel_invoke_method(g_channel, method, args, nullptr, nullptr, nullptr);
}

// A close request only docks. Dart removes this view's root before destroying
// its native window; camera capture, audio and call membership remain owned by
// the session. Each callback addresses its own entry, including during shutdown.
gboolean on_delete(GtkWidget*, GdkEvent*, gpointer data) {
  notify_view("closeRequested", static_cast<Popout*>(data));
  return TRUE;
}

gboolean on_key_press(GtkWidget*, GdkEventKey* event, gpointer data) {
  auto* entry = static_cast<Popout*>(data);
  if (entry->fullscreen && event->keyval == GDK_KEY_Escape) {
    gtk_window_unfullscreen(entry->window);
    return TRUE;
  }
  return FALSE;
}

gboolean on_window_state(GtkWidget*, GdkEventWindowState* event, gpointer data) {
  if ((event->changed_mask & GDK_WINDOW_STATE_FULLSCREEN) == 0) return FALSE;
  auto* entry = static_cast<Popout*>(data);
  entry->fullscreen = (event->new_window_state & GDK_WINDOW_STATE_FULLSCREEN) != 0;
  notify_view("fullscreenChanged", entry);
  return FALSE;
}

void on_destroy(GtkWidget* widget, gpointer data) {
  auto* entry = static_cast<Popout*>(data);
  const int64_t id = entry->view_id;
  notify_view("closed", entry);
  // No signal may retain a pointer after the registry releases this entry.
  g_signal_handlers_disconnect_by_data(widget, data);
  g_windows.erase(id);
}

void destroy_window(int64_t id) {
  auto it = g_windows.find(id);
  if (it != g_windows.end()) gtk_widget_destroy(GTK_WIDGET(it->second->window));
}

void on_main_window_destroy(GtkWidget*, gpointer) {
  g_shutting_down = true;
  while (!g_windows.empty()) destroy_window(g_windows.begin()->first);
  g_main_window = nullptr;
}

const gchar* lookup_string(FlValue* args, const char* key) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) return nullptr;
  FlValue* value = fl_value_lookup_string(args, key);
  return value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_STRING
      ? fl_value_get_string(value) : nullptr;
}

int64_t lookup_int(FlValue* args, const char* key, int64_t fallback) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) return fallback;
  FlValue* value = fl_value_lookup_string(args, key);
  return value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_INT
      ? fl_value_get_int(value) : fallback;
}

bool lookup_bool(FlValue* args, const char* key) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) return false;
  FlValue* value = fl_value_lookup_string(args, key);
  return value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_BOOL && fl_value_get_bool(value);
}

int64_t open_window(FlValue* args) {
  if (g_shutting_down || g_main_window == nullptr) return -1;
  const auto request_id = lookup_int(args, "requestId", -1);
  if (request_id < 0) return -1;
  GtkWidget* window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  const gchar* title = lookup_string(args, "title");
  gtk_window_set_title(GTK_WINDOW(window), title != nullptr ? title : "Vommet");
  gtk_window_set_icon(GTK_WINDOW(window), gtk_window_get_icon(g_main_window));
  GtkApplication* app = gtk_window_get_application(g_main_window);
  if (app != nullptr) gtk_window_set_application(GTK_WINDOW(window), app);
  const int min_width = static_cast<int>(lookup_int(args, "minWidth", 0));
  const int min_height = static_cast<int>(lookup_int(args, "minHeight", 0));
  gtk_window_set_default_size(GTK_WINDOW(window),
      static_cast<int>(MAX(lookup_int(args, "width", 960), MAX(min_width, 1))),
      static_cast<int>(MAX(lookup_int(args, "height", 600), MAX(min_height, 1))));
  if (min_width > 0 && min_height > 0) {
    GdkGeometry geometry = {};
    geometry.min_width = min_width;
    geometry.min_height = min_height;
    gtk_window_set_geometry_hints(GTK_WINDOW(window), nullptr, &geometry, GDK_HINT_MIN_SIZE);
  }
  FlView* view = fl_view_new_for_engine(g_engine);
  GdkRGBA black = {0, 0, 0, 1};
  fl_view_set_background_color(view, &black);
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));
  // Realize the view before reading its ID (which may be -1 until assigned).
  gtk_widget_show_all(window);
  const int64_t id = fl_view_get_id(view);
  if (id < 0 || g_windows.find(id) != g_windows.end()) {
    gtk_widget_destroy(window);
    return -1;
  }
  auto entry = std::make_unique<Popout>();
  entry->window = GTK_WINDOW(window);
  entry->view_id = id;
  entry->request_id = request_id;
  auto* data = entry.get();
  g_windows.emplace(id, std::move(entry));
  g_signal_connect(window, "delete-event", G_CALLBACK(on_delete), data);
  g_signal_connect(window, "key-press-event", G_CALLBACK(on_key_press), data);
  g_signal_connect(window, "window-state-event", G_CALLBACK(on_window_state), data);
  g_signal_connect(window, "destroy", G_CALLBACK(on_destroy), data);
  gtk_widget_grab_focus(GTK_WIDGET(view));
  return id;
}

void on_method_call(FlMethodChannel*, FlMethodCall* call, gpointer) {
  const gchar* method = fl_method_call_get_name(call);
  FlValue* args = fl_method_call_get_args(call);
  if (strcmp(method, "isAvailable") == 0) {
    g_autoptr(FlValue) yes = fl_value_new_bool(!g_shutting_down);
    fl_method_call_respond_success(call, yes, nullptr);
    return;
  }
  if (strcmp(method, "open") == 0) {
    const int64_t id = open_window(args);
    if (id < 0) {
      fl_method_call_respond_error(call, "window-unavailable", "Could not open the video window", nullptr, nullptr);
    } else {
      g_autoptr(FlValue) value = fl_value_new_int(id);
      fl_method_call_respond_success(call, value, nullptr);
    }
    return;
  }
  const auto id = lookup_int(args, "viewId", -1);
  auto it = g_windows.find(id);
  Popout* entry = it != g_windows.end() ? it->second.get() : nullptr;
  if (strcmp(method, "close") == 0) {
    destroy_window(id);
  } else if (strcmp(method, "setTitle") == 0) {
    const gchar* title = lookup_string(args, "title");
    if (entry != nullptr && title != nullptr) gtk_window_set_title(entry->window, title);
  } else if (strcmp(method, "setFullscreen") == 0) {
    if (entry != nullptr) {
      if (lookup_bool(args, "fullscreen")) gtk_window_fullscreen(entry->window);
      else gtk_window_unfullscreen(entry->window);
    }
  } else if (strcmp(method, "focus") == 0) {
    if (entry != nullptr) gtk_window_present(entry->window);
  } else {
    fl_method_call_respond_not_implemented(call, nullptr);
    return;
  }
  // Closing a stale/already closed ID is deliberately idempotent.
  fl_method_call_respond_success(call, nullptr, nullptr);
}
}  // namespace

void stream_popout_register(FlView* view, GtkWindow* main_window) {
  g_engine = fl_view_get_engine(view);
  g_main_window = main_window;
  g_shutting_down = false;
  g_signal_connect(main_window, "destroy", G_CALLBACK(on_main_window_destroy), nullptr);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_channel = fl_method_channel_new(fl_engine_get_binary_messenger(g_engine),
      "vommet/stream_popout", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(g_channel, on_method_call, nullptr, nullptr);
}
