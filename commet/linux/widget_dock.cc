#include "widget_dock.h"

#include <cairo.h>
#include <webkit2/webkit2.h>

#include <map>
#include <string>

// Vommet: see widget_dock.h. One entry per open widget, keyed by the id the
// Dart side gave it. A docked view is an overlay child of the main window,
// placed by on_get_child_position; a popped out view is the only child of
// its own window.

namespace {

struct DockEntry {
  std::string id;
  std::string title;
  WebKitWebView* view = nullptr;
  WebKitUserContentManager* content = nullptr;
  GtkWindow* popout = nullptr;
  GdkRectangle rect = {0, 0, 0, 0};  // GTK logical pixels, in the overlay
  bool visible = false;
};

FlView* g_flutter_view = nullptr;
GtkOverlay* g_overlay = nullptr;
FlMethodChannel* g_channel = nullptr;
std::map<std::string, DockEntry*> g_entries;

void notify(const char* method, DockEntry* entry, FlValue* extra = nullptr) {
  g_autoptr(FlValue) args = fl_value_new_map();
  fl_value_set_string_take(args, "id", fl_value_new_string(entry->id.c_str()));
  if (extra != nullptr) {
    fl_value_set_string(args, "message", extra);
  }
  fl_method_channel_invoke_method(g_channel, method, args, nullptr, nullptr,
                                  nullptr);
}

DockEntry* find_by_view(GtkWidget* widget) {
  for (auto& pair : g_entries) {
    if (GTK_WIDGET(pair.second->view) == widget) {
      return pair.second;
    }
  }
  return nullptr;
}

void apply_docked_visibility(DockEntry* entry) {
  if (entry->popout != nullptr) {
    return;
  }
  bool show = entry->visible && entry->rect.width > 0 && entry->rect.height > 0;
  gtk_widget_set_visible(GTK_WIDGET(entry->view), show);
  gtk_widget_queue_resize(GTK_WIDGET(g_overlay));
}

gboolean on_get_child_position(GtkOverlay* overlay, GtkWidget* widget,
                               GdkRectangle* allocation, gpointer) {
  DockEntry* entry = find_by_view(widget);
  if (entry == nullptr) {
    return FALSE;
  }
  *allocation = entry->rect;
  return TRUE;
}

// Messages from the page (widgets_ipc.js sendIpc) go to Dart unchanged.
void on_script_message(WebKitUserContentManager*, WebKitJavascriptResult* result,
                       gpointer user_data) {
  auto* entry = static_cast<DockEntry*>(user_data);
  JSCValue* value = webkit_javascript_result_get_js_value(result);
  g_autofree gchar* text = jsc_value_to_string(value);
  g_autoptr(FlValue) message = fl_value_new_string(text);
  notify("message", entry, message);
}

// The autoplay policy can only be given with a navigation decision, so
// every navigation is allowed with it (as the widget window does).
gboolean on_decide_policy(WebKitWebView*, WebKitPolicyDecision* decision,
                          WebKitPolicyDecisionType type, gpointer) {
  if (type != WEBKIT_POLICY_DECISION_TYPE_NAVIGATION_ACTION) {
    return FALSE;
  }
  WebKitWebsitePolicies* policies = webkit_website_policies_new_with_policies(
      "autoplay", WEBKIT_AUTOPLAY_ALLOW, nullptr);
  webkit_policy_decision_use_with_policies(decision, policies);
  g_object_unref(policies);
  return TRUE;
}

void on_media_permission_response(GtkDialog* dialog, gint response,
                                  gpointer user_data) {
  auto* request = WEBKIT_PERMISSION_REQUEST(user_data);
  if (response == GTK_RESPONSE_ACCEPT) {
    webkit_permission_request_allow(request);
  } else {
    webkit_permission_request_deny(request);
  }
  g_object_unref(request);
  gtk_widget_destroy(GTK_WIDGET(dialog));
}

// Microphone/camera: ask first. Everything else is denied.
gboolean on_permission_request(WebKitWebView* view,
                               WebKitPermissionRequest* request, gpointer) {
  if (!WEBKIT_IS_USER_MEDIA_PERMISSION_REQUEST(request)) {
    webkit_permission_request_deny(request);
    return TRUE;
  }
  GtkWidget* toplevel = gtk_widget_get_toplevel(GTK_WIDGET(view));
  GtkWidget* dialog = gtk_message_dialog_new(
      GTK_IS_WINDOW(toplevel) ? GTK_WINDOW(toplevel) : nullptr,
      static_cast<GtkDialogFlags>(GTK_DIALOG_MODAL |
                                  GTK_DIALOG_DESTROY_WITH_PARENT),
      GTK_MESSAGE_QUESTION, GTK_BUTTONS_NONE,
      "This widget wants to use your microphone or camera.");
  gtk_dialog_add_button(GTK_DIALOG(dialog), "Block", GTK_RESPONSE_REJECT);
  gtk_dialog_add_button(GTK_DIALOG(dialog), "Allow", GTK_RESPONSE_ACCEPT);
  gtk_dialog_set_default_response(GTK_DIALOG(dialog), GTK_RESPONSE_REJECT);
  g_signal_connect(dialog, "response",
                   G_CALLBACK(on_media_permission_response),
                   g_object_ref(request));
  gtk_widget_show_all(dialog);
  return TRUE;
}

// Links that open a new window go to the default browser (through the
// portal in the Flatpak).
GtkWidget* on_create(WebKitWebView* view, WebKitNavigationAction* action,
                     gpointer) {
  WebKitURIRequest* request = webkit_navigation_action_get_request(action);
  const gchar* uri = webkit_uri_request_get_uri(request);
  GtkWidget* toplevel = gtk_widget_get_toplevel(GTK_WIDGET(view));
  gtk_show_uri_on_window(GTK_IS_WINDOW(toplevel) ? GTK_WINDOW(toplevel) : nullptr,
                         uri, GDK_CURRENT_TIME, nullptr);
  return nullptr;
}

gboolean on_focus_in(GtkWidget*, GdkEvent*, gpointer user_data) {
  notify("focused", static_cast<DockEntry*>(user_data));
  return FALSE;
}

void on_web_process_terminated(WebKitWebView*,
                               WebKitWebProcessTerminationReason reason,
                               gpointer user_data) {
  g_warning("Widget web process ended (%d)", reason);
  notify("closed", static_cast<DockEntry*>(user_data));
}

void dock_back(DockEntry* entry);

gboolean on_popout_delete(GtkWidget*, GdkEvent*, gpointer user_data) {
  dock_back(static_cast<DockEntry*>(user_data));
  return TRUE;
}

// Moves the view between containers. A ref keeps it (and its page) alive
// while it has no parent.
void reparent(GtkWidget* view, GtkContainer* from, GtkWidget* to) {
  g_object_ref(view);
  gtk_container_remove(from, view);
  if (GTK_IS_OVERLAY(to)) {
    gtk_overlay_add_overlay(GTK_OVERLAY(to), view);
  } else {
    gtk_container_add(GTK_CONTAINER(to), view);
  }
  g_object_unref(view);
}

void pop_out(DockEntry* entry) {
  if (entry->popout != nullptr) {
    gtk_window_present(entry->popout);
    return;
  }
  GtkWidget* window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  g_autofree gchar* title = g_strdup_printf("Vommet | %s", entry->title.c_str());
  gtk_window_set_title(GTK_WINDOW(window), title);
  GtkWidget* main_window = gtk_widget_get_toplevel(GTK_WIDGET(g_overlay));
  if (GTK_IS_WINDOW(main_window)) {
    gtk_window_set_icon(GTK_WINDOW(window), gtk_window_get_icon(GTK_WINDOW(main_window)));
    GtkApplication* app = gtk_window_get_application(GTK_WINDOW(main_window));
    if (app != nullptr) {
      gtk_window_set_application(GTK_WINDOW(window), app);
    }
  }
  gtk_window_set_default_size(GTK_WINDOW(window),
                              MAX(entry->rect.width, 960),
                              MAX(entry->rect.height, 600));
  reparent(GTK_WIDGET(entry->view), GTK_CONTAINER(g_overlay), window);
  entry->popout = GTK_WINDOW(window);
  g_signal_connect(window, "delete-event", G_CALLBACK(on_popout_delete), entry);
  gtk_widget_show(GTK_WIDGET(entry->view));
  gtk_widget_show(window);
  notify("poppedOut", entry);
}

void dock_back(DockEntry* entry) {
  if (entry->popout == nullptr) {
    return;
  }
  GtkWindow* window = entry->popout;
  entry->popout = nullptr;
  g_signal_handlers_disconnect_by_data(window, entry);
  reparent(GTK_WIDGET(entry->view), GTK_CONTAINER(window),
           GTK_WIDGET(g_overlay));
  gtk_widget_destroy(GTK_WIDGET(window));
  apply_docked_visibility(entry);
  notify("docked", entry);
}

void destroy_entry(DockEntry* entry) {
  g_signal_handlers_disconnect_by_data(entry->content, entry);
  g_signal_handlers_disconnect_by_data(entry->view, entry);
  if (entry->popout != nullptr) {
    g_signal_handlers_disconnect_by_data(entry->popout, entry);
    gtk_widget_destroy(GTK_WIDGET(entry->popout));
  } else {
    gtk_widget_destroy(GTK_WIDGET(entry->view));
  }
  g_object_unref(entry->content);
  g_entries.erase(entry->id);
  delete entry;
}

DockEntry* create_entry(const std::string& id, const gchar* url,
                        const gchar* script, const gchar* title,
                        const gchar* user_agent) {
  auto* entry = new DockEntry();
  entry->id = id;
  entry->title = title;
  entry->content = webkit_user_content_manager_new();
  webkit_user_content_manager_register_script_message_handler(entry->content,
                                                              "vommetIpc");
  g_signal_connect(entry->content, "script-message-received::vommetIpc",
                   G_CALLBACK(on_script_message), entry);
  WebKitUserScript* user_script = webkit_user_script_new(
      script, WEBKIT_USER_CONTENT_INJECT_TOP_FRAME,
      WEBKIT_USER_SCRIPT_INJECT_AT_DOCUMENT_START, nullptr, nullptr);
  webkit_user_content_manager_add_script(entry->content, user_script);
  webkit_user_script_unref(user_script);

  // Like the widget window: nothing is kept between sessions.
  g_autoptr(WebKitWebContext) context = webkit_web_context_new_ephemeral();
  entry->view = WEBKIT_WEB_VIEW(g_object_new(
      WEBKIT_TYPE_WEB_VIEW, "web-context", context, "user-content-manager",
      entry->content, nullptr));

  WebKitSettings* settings = webkit_web_view_get_settings(entry->view);
  webkit_settings_set_enable_webrtc(settings, TRUE);
  webkit_settings_set_enable_media_stream(settings, TRUE);
  if (user_agent != nullptr && *user_agent != '\0') {
    webkit_settings_set_user_agent(settings, user_agent);
  }

  g_signal_connect(entry->view, "decide-policy", G_CALLBACK(on_decide_policy),
                   entry);
  g_signal_connect(entry->view, "permission-request",
                   G_CALLBACK(on_permission_request), entry);
  g_signal_connect(entry->view, "create", G_CALLBACK(on_create), entry);
  g_signal_connect(entry->view, "focus-in-event", G_CALLBACK(on_focus_in),
                   entry);
  g_signal_connect(entry->view, "web-process-terminated",
                   G_CALLBACK(on_web_process_terminated), entry);

  gtk_overlay_add_overlay(g_overlay, GTK_WIDGET(entry->view));
  gtk_widget_set_visible(GTK_WIDGET(entry->view), FALSE);
  webkit_web_view_load_uri(entry->view, url);
  g_entries[id] = entry;
  return entry;
}

cairo_status_t append_png(void* closure, const unsigned char* data,
                          unsigned int length) {
  g_byte_array_append(static_cast<GByteArray*>(closure), data, length);
  return CAIRO_STATUS_SUCCESS;
}

void on_snapshot(GObject* source, GAsyncResult* result, gpointer user_data) {
  auto* call = FL_METHOD_CALL(user_data);
  g_autoptr(GError) error = nullptr;
  cairo_surface_t* surface = webkit_web_view_get_snapshot_finish(
      WEBKIT_WEB_VIEW(source), result, &error);
  if (surface == nullptr) {
    fl_method_call_respond_success(call, nullptr, nullptr);
    g_object_unref(call);
    return;
  }
  GByteArray* png = g_byte_array_new();
  cairo_surface_write_to_png_stream(surface, append_png, png);
  cairo_surface_destroy(surface);
  g_autoptr(FlValue) value = fl_value_new_uint8_list(png->data, png->len);
  g_byte_array_unref(png);
  fl_method_call_respond_success(call, value, nullptr);
  g_object_unref(call);
}

const gchar* lookup_string(FlValue* args, const char* key) {
  FlValue* value = fl_value_lookup_string(args, key);
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_STRING) {
    return nullptr;
  }
  return fl_value_get_string(value);
}

double lookup_double(FlValue* args, const char* key) {
  FlValue* value = fl_value_lookup_string(args, key);
  if (value == nullptr) {
    return 0;
  }
  if (fl_value_get_type(value) == FL_VALUE_TYPE_FLOAT) {
    return fl_value_get_float(value);
  }
  if (fl_value_get_type(value) == FL_VALUE_TYPE_INT) {
    return static_cast<double>(fl_value_get_int(value));
  }
  return 0;
}

void on_method_call(FlMethodChannel*, FlMethodCall* call, gpointer) {
  const gchar* method = fl_method_call_get_name(call);
  FlValue* args = fl_method_call_get_args(call);

  if (strcmp(method, "isAvailable") == 0) {
    g_autoptr(FlValue) yes = fl_value_new_bool(TRUE);
    fl_method_call_respond_success(call, yes, nullptr);
    return;
  }

  if (strcmp(method, "focusFlutter") == 0) {
    gtk_widget_grab_focus(GTK_WIDGET(g_flutter_view));
    fl_method_call_respond_success(call, nullptr, nullptr);
    return;
  }

  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    fl_method_call_respond_error(call, "bad_args", "expected a map", nullptr,
                                 nullptr);
    return;
  }
  const gchar* id = lookup_string(args, "id");
  if (id == nullptr) {
    fl_method_call_respond_error(call, "bad_args", "missing id", nullptr,
                                 nullptr);
    return;
  }

  if (strcmp(method, "create") == 0) {
    const gchar* url = lookup_string(args, "url");
    const gchar* script = lookup_string(args, "script");
    const gchar* title = lookup_string(args, "title");
    if (url == nullptr || script == nullptr || g_entries.count(id) != 0) {
      fl_method_call_respond_error(call, "bad_args", "bad create", nullptr,
                                   nullptr);
      return;
    }
    create_entry(id, url, script, title == nullptr ? "Widget" : title,
                 lookup_string(args, "userAgent"));
    fl_method_call_respond_success(call, nullptr, nullptr);
    return;
  }

  auto found = g_entries.find(id);
  if (found == g_entries.end()) {
    fl_method_call_respond_error(call, "unknown_id", id, nullptr, nullptr);
    return;
  }
  DockEntry* entry = found->second;

  if (strcmp(method, "setRect") == 0) {
    // Dart sends physical pixels; GTK places widgets in logical ones.
    int scale = gtk_widget_get_scale_factor(GTK_WIDGET(g_overlay));
    entry->rect.x = static_cast<int>(lookup_double(args, "x") / scale);
    entry->rect.y = static_cast<int>(lookup_double(args, "y") / scale);
    entry->rect.width = static_cast<int>(lookup_double(args, "width") / scale);
    entry->rect.height =
        static_cast<int>(lookup_double(args, "height") / scale);
    apply_docked_visibility(entry);
  } else if (strcmp(method, "setVisible") == 0) {
    FlValue* visible = fl_value_lookup_string(args, "visible");
    entry->visible = visible != nullptr &&
                     fl_value_get_type(visible) == FL_VALUE_TYPE_BOOL &&
                     fl_value_get_bool(visible);
    apply_docked_visibility(entry);
  } else if (strcmp(method, "evaluate") == 0) {
    const gchar* script = lookup_string(args, "script");
    if (script != nullptr) {
      webkit_web_view_evaluate_javascript(entry->view, script, -1, nullptr,
                                          nullptr, nullptr, nullptr, nullptr);
    }
  } else if (strcmp(method, "popOut") == 0) {
    pop_out(entry);
  } else if (strcmp(method, "dockBack") == 0) {
    dock_back(entry);
  } else if (strcmp(method, "snapshot") == 0) {
    webkit_web_view_get_snapshot(entry->view, WEBKIT_SNAPSHOT_REGION_VISIBLE,
                                 WEBKIT_SNAPSHOT_OPTIONS_NONE, nullptr,
                                 on_snapshot, g_object_ref(call));
    return;
  } else if (strcmp(method, "destroy") == 0) {
    destroy_entry(entry);
  } else {
    fl_method_call_respond_not_implemented(call, nullptr);
    return;
  }
  fl_method_call_respond_success(call, nullptr, nullptr);
}

}  // namespace

void widget_dock_register(FlView* view, GtkOverlay* overlay) {
  g_flutter_view = view;
  g_overlay = overlay;
  g_signal_connect(overlay, "get-child-position",
                   G_CALLBACK(on_get_child_position), nullptr);

  g_autoptr(FlPluginRegistrar) registrar =
      fl_plugin_registry_get_registrar_for_plugin(FL_PLUGIN_REGISTRY(view),
                                                  "VommetWidgetDock");
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar), "vommet/widget_dock",
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(g_channel, on_method_call, nullptr,
                                            nullptr);
}
