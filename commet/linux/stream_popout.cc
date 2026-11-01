#include "stream_popout.h"

#include <gdk/gdkkeysyms.h>

#include <cstring>

// Vommet: see stream_popout.h.

namespace {

FlEngine* g_engine = nullptr;
GtkWindow* g_main_window = nullptr;
FlMethodChannel* g_channel = nullptr;
GtkWindow* g_window = nullptr;
FlView* g_view = nullptr;
bool g_fullscreen = false;

void notify(const char* method, FlValue* args) {
  fl_method_channel_invoke_method(g_channel, method, args, nullptr, nullptr,
                                  nullptr);
}

void notify_view(const char* method) {
  g_autoptr(FlValue) args = fl_value_new_map();
  fl_value_set_string_take(args, "viewId",
                           fl_value_new_int(fl_view_get_id(g_view)));
  notify(method, args);
}

bool is_ours(GtkWidget* widget) {
  return g_window != nullptr && widget == GTK_WIDGET(g_window);
}

// The window manager's close button (or Alt+F4): Dart docks the stream back
// and then closes the window itself (see stream_popout.h).
gboolean on_delete(GtkWidget* widget, GdkEvent*, gpointer) {
  if (is_ours(widget)) {
    notify_view("closeRequested");
  }
  return TRUE;
}

// Esc leaves full screen. Connected handlers run before GtkWindow's own,
// which hands the key to the Flutter view.
gboolean on_key_press(GtkWidget* widget, GdkEventKey* event, gpointer) {
  if (is_ours(widget) && g_fullscreen && event->keyval == GDK_KEY_Escape) {
    gtk_window_unfullscreen(g_window);
    return TRUE;
  }
  return FALSE;
}

gboolean on_window_state(GtkWidget* widget, GdkEventWindowState* event,
                         gpointer) {
  if (!is_ours(widget) ||
      (event->changed_mask & GDK_WINDOW_STATE_FULLSCREEN) == 0) {
    return FALSE;
  }
  g_fullscreen = (event->new_window_state & GDK_WINDOW_STATE_FULLSCREEN) != 0;
  g_autoptr(FlValue) args = fl_value_new_map();
  fl_value_set_string_take(args, "viewId",
                           fl_value_new_int(fl_view_get_id(g_view)));
  fl_value_set_string_take(args, "fullscreen", fl_value_new_bool(g_fullscreen));
  notify("fullscreenChanged", args);
  return FALSE;
}

void destroy_window() {
  if (g_window == nullptr) {
    return;
  }
  GtkWindow* window = g_window;
  g_window = nullptr;
  g_view = nullptr;
  g_fullscreen = false;
  // Destroying the window disposes the FlView, which removes the view from
  // the engine.
  gtk_widget_destroy(GTK_WIDGET(window));
}

// The main window goes (the app quits): the pop-out goes with it, so the
// app doesn't keep running in a window of its own.
void on_main_window_destroy(GtkWidget*, gpointer) {
  if (g_window != nullptr) {
    notify_view("closed");
  }
  destroy_window();
}

const gchar* lookup_string(FlValue* args, const char* key) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return nullptr;
  }
  FlValue* value = fl_value_lookup_string(args, key);
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_STRING) {
    return nullptr;
  }
  return fl_value_get_string(value);
}

int lookup_int(FlValue* args, const char* key, int fallback) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return fallback;
  }
  FlValue* value = fl_value_lookup_string(args, key);
  if (value == nullptr) {
    return fallback;
  }
  if (fl_value_get_type(value) == FL_VALUE_TYPE_INT) {
    return static_cast<int>(fl_value_get_int(value));
  }
  if (fl_value_get_type(value) == FL_VALUE_TYPE_FLOAT) {
    return static_cast<int>(fl_value_get_float(value));
  }
  return fallback;
}

bool lookup_bool(FlValue* args, const char* key) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return false;
  }
  FlValue* value = fl_value_lookup_string(args, key);
  return value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_BOOL &&
         fl_value_get_bool(value);
}

// Opens the window (or brings the open one forward) and returns its
// Flutter view id.
int64_t open_window(const gchar* title, int width, int height) {
  if (g_window != nullptr) {
    if (title != nullptr) {
      gtk_window_set_title(g_window, title);
    }
    gtk_window_present(g_window);
    return fl_view_get_id(g_view);
  }
  GtkWidget* window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  gtk_window_set_title(GTK_WINDOW(window), title != nullptr ? title : "Vommet");
  if (g_main_window != nullptr) {
    gtk_window_set_icon(GTK_WINDOW(window), gtk_window_get_icon(g_main_window));
    GtkApplication* app = gtk_window_get_application(g_main_window);
    if (app != nullptr) {
      gtk_window_set_application(GTK_WINDOW(window), app);
    }
  }
  gtk_window_set_default_size(GTK_WINDOW(window), MAX(width, 320),
                              MAX(height, 180));

  FlView* view = fl_view_new_for_engine(g_engine);
  GdkRGBA black = {0, 0, 0, 1};
  fl_view_set_background_color(view, &black);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  g_window = GTK_WINDOW(window);
  g_view = view;
  g_fullscreen = false;
  g_signal_connect(window, "delete-event", G_CALLBACK(on_delete), nullptr);
  g_signal_connect(window, "key-press-event", G_CALLBACK(on_key_press),
                   nullptr);
  g_signal_connect(window, "window-state-event", G_CALLBACK(on_window_state),
                   nullptr);
  gtk_widget_show(window);
  gtk_widget_grab_focus(GTK_WIDGET(view));
  return fl_view_get_id(view);
}

void on_method_call(FlMethodChannel*, FlMethodCall* call, gpointer) {
  const gchar* method = fl_method_call_get_name(call);
  FlValue* args = fl_method_call_get_args(call);

  if (strcmp(method, "isAvailable") == 0) {
    g_autoptr(FlValue) yes = fl_value_new_bool(TRUE);
    fl_method_call_respond_success(call, yes, nullptr);
    return;
  }
  if (strcmp(method, "open") == 0) {
    int64_t id = open_window(lookup_string(args, "title"),
                             lookup_int(args, "width", 960),
                             lookup_int(args, "height", 600));
    g_autoptr(FlValue) value = fl_value_new_int(id);
    fl_method_call_respond_success(call, value, nullptr);
    return;
  }
  if (strcmp(method, "close") == 0) {
    destroy_window();
  } else if (strcmp(method, "setTitle") == 0) {
    const gchar* title = lookup_string(args, "title");
    if (g_window != nullptr && title != nullptr) {
      gtk_window_set_title(g_window, title);
    }
  } else if (strcmp(method, "setFullscreen") == 0) {
    if (g_window != nullptr) {
      if (lookup_bool(args, "fullscreen")) {
        gtk_window_fullscreen(g_window);
      } else {
        gtk_window_unfullscreen(g_window);
      }
    }
  } else if (strcmp(method, "focus") == 0) {
    if (g_window != nullptr) {
      gtk_window_present(g_window);
    }
  } else {
    fl_method_call_respond_not_implemented(call, nullptr);
    return;
  }
  fl_method_call_respond_success(call, nullptr, nullptr);
}

}  // namespace

void stream_popout_register(FlView* view, GtkWindow* main_window) {
  g_engine = fl_view_get_engine(view);
  g_main_window = main_window;
  g_signal_connect(main_window, "destroy", G_CALLBACK(on_main_window_destroy),
                   nullptr);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_channel = fl_method_channel_new(fl_engine_get_binary_messenger(g_engine),
                                    "vommet/stream_popout",
                                    FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(g_channel, on_method_call, nullptr,
                                            nullptr);
}
