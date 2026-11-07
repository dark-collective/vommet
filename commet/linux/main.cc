#include "my_application.h"
#include "shortcuts.h"
#include "widget_runner.h"
#include "overlay_runner.h"

#include <sys/resource.h>

// Vommet: many desktops start apps with a soft limit of 1,024 open files.
// Sockets, the databases, the image cache and fonts all count, and a large
// account's start came close (a FileSystemException from File.open during
// a burst of requests). Raise the soft limit towards the hard one, like
// browsers do; 8,192 keeps select()-based code in libraries safe enough
// (they only see descriptors handed to them).
static void raise_open_file_limit()
{
  struct rlimit limit;
  if (getrlimit(RLIMIT_NOFILE, &limit) != 0)
    return;
  rlim_t wanted = 8192;
  if (limit.rlim_max != RLIM_INFINITY && wanted > limit.rlim_max)
    wanted = limit.rlim_max;
  if (limit.rlim_cur != RLIM_INFINITY && limit.rlim_cur < wanted)
  {
    limit.rlim_cur = wanted;
    setrlimit(RLIMIT_NOFILE, &limit);
  }
}

int main(int argc, char **argv)
{
  raise_open_file_limit();

  // flutter run -d linux --dart-entrypoint-args --shortcut,mute
  int is_shortcut = shortcuts_main(argc, argv);
  if (is_shortcut != 0)
  {
    return is_shortcut;
  }

  // flutter run -d linux --dart-entrypoint-args --widget_runner
  int is_widget_runner = widget_runner(argc, argv);
  if (is_widget_runner != 0)
  {
    return is_widget_runner;
  }

  // flutter run -d linux --dart-entrypoint-args --overlay
  int is_overlay = overlay_runner(argc, argv);
  if(is_overlay != 0) 
  {
    return is_overlay;
  }

  if (is_shortcut == 0)
  {
    // Vommet: name the X11 window class after the app id so docks and task
    // bars match the window to im.nether.chat.desktop (StartupWMClass) and
    // show its icon; by default GTK uses the executable name ("vommet").
    g_set_prgname(APPLICATION_ID);

    g_autoptr(MyApplication) app = my_application_new();
    return g_application_run(G_APPLICATION(app), argc, argv);
  }
}
