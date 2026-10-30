#ifndef RUNNER_WIDGET_DOCK_H_
#define RUNNER_WIDGET_DOCK_H_

#include <flutter/binary_messenger.h>
#include <windows.h>

// Vommet: docked widgets (experiment "Docked widgets"). A WebView2 view is
// placed over the rectangle the Dart side keeps free in the main window
// (channel "vommet/widget_dock", same contract as linux/widget_dock.cc) and
// can move into a window of its own and back without reloading.
void WidgetDockRegister(flutter::BinaryMessenger* messenger, HWND flutter_view);

// Main window messages the docked views need to follow (moves).
void WidgetDockOnMainWindowMessage(UINT message);

// Closes every view, docked or popped out.
void WidgetDockShutdown();

#endif  // RUNNER_WIDGET_DOCK_H_
