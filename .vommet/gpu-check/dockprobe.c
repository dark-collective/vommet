// LD_PRELOAD probe for the Vommet Linux widget dock, run against a released
// binary on a real GPU. It intercepts the "vommet/widget_dock" method channel
// that the runner registers at startup, then drives the shipped (compiled)
// handler directly: create a test page, dock it, pop it out, dock it back,
// full screen docked and popped out, and destroy while full screen. Checks
// are on compositor screenshots (weston-screenshooter), so the same probe
// works on Wayland and on X11 (Xwayland) and sees what a user would see.
//
// Results go to stdout as PASS/FAIL lines and a final RESULT line.
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <gdk/gdkwayland.h>
#include <gtk/gtk.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct _FlMethodChannel FlMethodChannel;
typedef struct _FlMethodCall FlMethodCall;
typedef struct _FlValue FlValue;
typedef void (*Handler)(FlMethodChannel*, FlMethodCall*, gpointer);

static FlMethodChannel* dock_channel;
static Handler dock_handler;
static gpointer dock_handler_data;
static FlMethodCall* fake_call;
static const char* fake_name;
static FlValue* fake_args;
static GPtrArray* events;
static int failures, step;
static GtkWindow* main_window;

#define REAL(name) ((__typeof__(&name))dlsym(RTLD_NEXT, #name))
#define FL(name) ((__typeof__(&name))dlsym(RTLD_DEFAULT, #name))

FlValue* fl_value_new_map(void);
FlValue* fl_value_new_string(const gchar*);
FlValue* fl_value_new_bool(gboolean);
FlValue* fl_value_new_float(double);
void fl_value_set_string_take(FlValue*, const gchar*, FlValue*);
void fl_value_unref(FlValue*);

FlMethodChannel* fl_method_channel_new(gpointer messenger, const gchar* name, gpointer codec) {
  FlMethodChannel* channel = REAL(fl_method_channel_new)(messenger, name, codec);
  if (g_strcmp0(name, "vommet/widget_dock") == 0) dock_channel = channel;
  return channel;
}

void fl_method_channel_set_method_call_handler(FlMethodChannel* channel, Handler handler,
                                               gpointer data, GDestroyNotify notify) {
  if (channel != NULL && channel == dock_channel) {
    dock_handler = handler;
    dock_handler_data = data;
  }
  REAL(fl_method_channel_set_method_call_handler)(channel, handler, data, notify);
}

void fl_method_channel_invoke_method(FlMethodChannel* channel, const gchar* method, FlValue* args,
                                     GCancellable* cancellable, GAsyncReadyCallback callback,
                                     gpointer data) {
  if (channel == dock_channel && events != NULL && g_strcmp0(method, "message") != 0) {
    printf("  event: %s\n", method);
    g_ptr_array_add(events, g_strdup(method));
  }
  REAL(fl_method_channel_invoke_method)(channel, method, args, cancellable, callback, data);
}

const gchar* fl_method_call_get_name(FlMethodCall* call) {
  return call == fake_call ? fake_name : REAL(fl_method_call_get_name)(call);
}
FlValue* fl_method_call_get_args(FlMethodCall* call) {
  return call == fake_call ? fake_args : REAL(fl_method_call_get_args)(call);
}
gboolean fl_method_call_respond_success(FlMethodCall* call, FlValue* result, GError** error) {
  return call == fake_call ? TRUE : REAL(fl_method_call_respond_success)(call, result, error);
}
gboolean fl_method_call_respond_error(FlMethodCall* call, const gchar* code, const gchar* message,
                                      FlValue* details, GError** error) {
  if (call == fake_call) {
    printf("  %s -> error %s\n", fake_name, code);
    return TRUE;
  }
  return REAL(fl_method_call_respond_error)(call, code, message, details, error);
}
gboolean fl_method_call_respond_not_implemented(FlMethodCall* call, GError** error) {
  if (call == fake_call) {
    printf("  %s -> not implemented\n", fake_name);
    return TRUE;
  }
  return REAL(fl_method_call_respond_not_implemented)(call, error);
}

// ---- driving the shipped handler -------------------------------------------
static FlValue* idargs(void) {
  FlValue* m = FL(fl_value_new_map)();
  FL(fl_value_set_string_take)(m, "id", FL(fl_value_new_string)("gpu-probe"));
  return m;
}
static void call(const char* method, FlValue* args) {
  fake_call = (FlMethodCall*)g_object_new(G_TYPE_OBJECT, NULL);
  fake_name = method;
  fake_args = args;
  dock_handler(dock_channel, fake_call, dock_handler_data);
  g_object_unref(fake_call);
  fake_call = NULL;
  FL(fl_value_unref)(args);
}
static void js(const char* script) {
  FlValue* a = idargs();
  FL(fl_value_set_string_take)(a, "script", FL(fl_value_new_string)(script));
  call("evaluate", a);
}
static void check(gboolean ok, const char* what) {
  printf("%s: %s\n", ok ? "PASS" : "FAIL", what);
  fflush(stdout);
  if (!ok) failures++;
}
static gboolean saw(const char* e) {
  for (guint i = 0; i < events->len; i++)
    if (strcmp(g_ptr_array_index(events, i), e) == 0) return TRUE;
  return FALSE;
}
static GtkWindow* other_toplevel(void) {
  GList* list = gtk_window_list_toplevels();
  GtkWindow* found = NULL;
  for (GList* l = list; l; l = l->next)
    if (l->data != main_window && gtk_widget_get_visible(l->data) &&
        gtk_window_get_window_type(l->data) == GTK_WINDOW_TOPLEVEL)
      found = l->data;
  g_list_free(list);
  return found;
}
static GtkWidget* find_web_view(GtkWidget* w) {
  if (g_str_has_prefix(G_OBJECT_TYPE_NAME(w), "WebKitWebView")) return w;
  if (!GTK_IS_CONTAINER(w)) return NULL;
  GList* kids = gtk_container_get_children(GTK_CONTAINER(w));
  GtkWidget* found = NULL;
  for (GList* l = kids; l && !found; l = l->next) found = find_web_view(l->data);
  g_list_free(kids);
  return found;
}
static gboolean is_fullscreen(GtkWindow* w) {
  GdkWindow* gw = w ? gtk_widget_get_window(GTK_WIDGET(w)) : NULL;
  return gw && (gdk_window_get_state(gw) & GDK_WINDOW_STATE_FULLSCREEN);
}

// Screenshot of the whole compositor output; counts of the page colours.
typedef struct { long blue, pink, black, total; } Counts;
static gboolean near(const guchar* p, int r, int g, int b) {
  return abs(p[0] - r) < 24 && abs(p[1] - g) < 24 && abs(p[2] - b) < 24;
}
static Counts shot(const char* tag) {
  Counts c = {0};
  const char* dir = g_getenv("PROBE_SHOTS");
  g_autofree char* cmd = g_strdup_printf(
      "cd '%s' && rm -f wayland-screenshot-*.png && weston-screenshooter >/dev/null 2>&1 && "
      "mv \"$(ls -t wayland-screenshot-*.png | head -1)\" '%s-%s.png'",
      dir, g_getenv("PROBE_LABEL"), tag);
  if (system(cmd) != 0) { printf("  screenshot failed (%s)\n", tag); return c; }
  g_autofree char* path = g_strdup_printf("%s/%s-%s.png", dir, g_getenv("PROBE_LABEL"), tag);
  GdkPixbuf* pb = gdk_pixbuf_new_from_file(path, NULL);
  if (!pb) return c;
  int w = gdk_pixbuf_get_width(pb), h = gdk_pixbuf_get_height(pb);
  int n = gdk_pixbuf_get_n_channels(pb), rs = gdk_pixbuf_get_rowstride(pb);
  const guchar* px = gdk_pixbuf_get_pixels(pb);
  for (int y = 0; y < h; y++)
    for (int x = 0; x < w; x++) {
      const guchar* p = px + y * rs + x * n;
      if (near(p, 0x33, 0x66, 0xcc)) c.blue++;
      else if (near(p, 0xcc, 0x33, 0x66)) c.pink++;
      else if (p[0] < 8 && p[1] < 8 && p[2] < 8) c.black++;
    }
  c.total = (long)w * h;
  g_object_unref(pb);
  printf("  [%s] page blue %ld, full screen pink %ld, black %ld of %ld px\n", tag, c.blue, c.pink, c.black, c.total);
  return c;
}

static const int RX = 120, RY = 100, RW = 400, RH = 300;
static gboolean wayland;

static gboolean tick(gpointer) {
  GtkWindow* pop;
  Counts c;
  switch (step++) {
  case 0: {
    c = shot("docked");
    check(c.blue >= RW * RH * 8 / 10, "docked view draws the page");
    call("popOut", idargs());
    break;
  }
  case 1:
    c = shot("popped");
    check(other_toplevel() != NULL, "popped out window exists");
    check(c.blue >= 200000, "popped out window draws the page (not black)");
    check(saw("poppedOut"), "poppedOut event");
    call("dockBack", idargs());
    break;
  case 2:
    c = shot("redocked");
    check(c.blue >= RW * RH * 8 / 10, "docked back draws the page");
    gtk_window_present(main_window);
    js("document.getElementById('v').requestFullscreen()");
    break;
  case 3:
    c = shot("fs-docked");
    check(saw("fullscreenEntered"), "fullscreenEntered event (docked)");
    check(is_fullscreen(main_window), "main window full screen");
    check(c.pink >= c.total * 8 / 10, "docked full screen covers the screen");
    g_ptr_array_set_size(events, 0);
    // Esc: a real key on X11; Wayland has no synthetic input here, so the
    // page leaves full screen itself (same WebKit leave path).
    if (wayland) {
      js("document.exitFullscreen()");
    } else {
      GtkWidget* view = find_web_view(GTK_WIDGET(main_window));
      if (view) gtk_widget_grab_focus(view);
      system("xdotool key Escape");
    }
    break;
  case 4:
    c = shot("left");
    check(saw("fullscreenLeft"), wayland ? "page exit: fullscreenLeft event" : "Esc: fullscreenLeft event");
    check(!is_fullscreen(main_window), "main window no longer full screen");
    check(c.blue >= RW * RH * 8 / 10 && c.pink < 1000, "view back on its rect, drawing the page");
    g_ptr_array_set_size(events, 0);
    call("popOut", idargs());
    break;
  case 5:
    js("document.getElementById('v').requestFullscreen()");
    break;
  case 6:
    c = shot("fs-popped");
    pop = other_toplevel();
    check(saw("fullscreenEntered"), "fullscreenEntered event (popped out)");
    check(is_fullscreen(pop), "popped out window full screen");
    check(!is_fullscreen(main_window), "main window left alone");
    check(c.pink >= c.total * 8 / 10, "popped out full screen draws the element (not black)");
    if (pop) gtk_window_unfullscreen(pop);  // the WM takes it out of full screen
    break;
  case 7:
    check(saw("fullscreenLeft"), "WM unfullscreen: fullscreenLeft event");
    call("dockBack", idargs());
    break;
  case 8:
    c = shot("end");
    check(c.blue >= RW * RH * 8 / 10, "docked after all that still draws the page");
    js("document.getElementById('v').requestFullscreen()");
    break;
  case 9:
    check(is_fullscreen(main_window), "full screen again before destroy");
    call("destroy", idargs());
    break;
  case 10:
    check(!is_fullscreen(main_window), "destroy while full screen restores the main window");
    printf(failures ? "RESULT FAIL (%d)\n" : "RESULT PASS\n", failures);
    fflush(stdout);
    _exit(failures ? 1 : 0);
  }
  return TRUE;
}

static gboolean start(gpointer) {
  static int waited;
  GList* list = gtk_window_list_toplevels();
  for (GList* l = list; l && !main_window; l = l->next)
    if (gtk_widget_get_visible(l->data)) main_window = l->data;
  g_list_free(list);
  if (++waited < 10 || dock_handler == NULL || main_window == NULL) {
    if (waited > 90) {
      printf("FAIL: dock channel or main window never appeared\nRESULT FAIL (setup)\n");
      fflush(stdout);
      _exit(2);
    }
    return TRUE;
  }
  printf("  dock channel captured; driving the shipped handler\n");
  wayland = GDK_IS_WAYLAND_DISPLAY(gdk_display_get_default());
  events = g_ptr_array_new_with_free_func(g_free);
  FlValue* a = idargs();
  g_autofree char* uri = g_strdup_printf("file://%s", g_getenv("PROBE_PAGE"));
  FL(fl_value_set_string_take)(a, "url", FL(fl_value_new_string)(uri));
  FL(fl_value_set_string_take)(a, "script", FL(fl_value_new_string)("window.__probe=1;"));
  FL(fl_value_set_string_take)(a, "title", FL(fl_value_new_string)("GPU probe"));
  call("create", a);
  // setRect takes physical pixels.
  int scale = gtk_widget_get_scale_factor(GTK_WIDGET(main_window));
  a = idargs();
  FL(fl_value_set_string_take)(a, "x", FL(fl_value_new_float)(RX * scale));
  FL(fl_value_set_string_take)(a, "y", FL(fl_value_new_float)(RY * scale));
  FL(fl_value_set_string_take)(a, "width", FL(fl_value_new_float)(RW * scale));
  FL(fl_value_set_string_take)(a, "height", FL(fl_value_new_float)(RH * scale));
  call("setRect", a);
  a = idargs();
  FL(fl_value_set_string_take)(a, "visible", FL(fl_value_new_bool)(TRUE));
  call("setVisible", a);
  g_timeout_add(3000, tick, NULL);
  return FALSE;
}

__attribute__((constructor)) static void probe_init(void) {
  // Only in the main app process, never in WebKit helper processes.
  if (g_getenv("PROBE_PAGE") == NULL || strstr(program_invocation_name, "WebKit")) return;
  unsetenv("LD_PRELOAD");
  g_timeout_add(1000, start, NULL);  // polls; gives Flutter ~10 s to draw
}
