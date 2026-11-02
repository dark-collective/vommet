#ifndef STREAM_POPOUT_H_
#define STREAM_POPOUT_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

// Vommet: a watched screen share in its own window ("vommet/stream_popout"
// method channel, lib/ui/organisms/call_view/stream_popout_window.dart).
//
// The window holds a second FlView on the app's own engine
// (fl_view_new_for_engine), so Dart draws into it from the same isolate and
// the stream's video texture, registered with that engine, shows there as
// it does in the main window. One pop-out at a time. Closing the window only
// asks Dart to dock the stream back; Dart takes the view out of its widget
// tree first and then calls close, which destroys the window. It also goes
// when the main window does (app quit).
void stream_popout_register(FlView* view, GtkWindow* main_window);

#endif  // STREAM_POPOUT_H_
