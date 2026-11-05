#pragma once

#include <cstring>

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

// Vommet: the title bar follows the app theme (Vommet issue 384). The window
// has no header bar, so GTK draws a plain client-side title bar with its own
// theme, which in the Flatpak is always light Adwaita. Dart
// (lib/config/title_bar_brightness.dart) sends setDarkTheme(bool) whenever
// the app theme's brightness or the Title bar setting changes, and GTK
// switches the theme's dark variant on or off for every window at once.
static void vommet_window_method_cb(FlMethodChannel* channel,
                                    FlMethodCall* method_call,
                                    gpointer user_data) {
  g_autoptr(FlMethodResponse) response = nullptr;
  if (strcmp(fl_method_call_get_name(method_call), "setDarkTheme") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_BOOL) {
      response = FL_METHOD_RESPONSE(
          fl_method_error_response_new("bad_args", "expected a bool", nullptr));
    } else {
      g_object_set(gtk_settings_get_default(),
                   "gtk-application-prefer-dark-theme",
                   fl_value_get_bool(args) ? TRUE : FALSE, nullptr);
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    }
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(method_call, response, nullptr);
}

// Registers the channel; it lives as long as the app.
static void vommet_window_theme_register(FlView* view) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  FlMethodChannel* channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "im.nether.vommet/window", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, vommet_window_method_cb,
                                            nullptr, nullptr);
}
