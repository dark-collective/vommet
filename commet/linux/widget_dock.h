#ifndef WIDGET_DOCK_H_
#define WIDGET_DOCK_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

// Vommet: widgets docked inside the main window.
//
// Flutter on Linux can't embed native views, so a widget's WebKitWebView is
// placed in a GtkOverlay above the Flutter view, over the rectangle the Dart
// side keeps free for it ("vommet/widget_dock" method channel). Popping a
// widget out moves the same view into its own window, and docking moves it
// back, so the page keeps running (no reload).
void widget_dock_register(FlView* view, GtkOverlay* overlay);

#endif  // WIDGET_DOCK_H_
