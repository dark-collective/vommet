#pragma once

#include <cstring>

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

// Vommet: frame counter (Vommet issue 350). Counts how often GTK redraws the
// main window, to tell "Flutter draws frames" apart from "the embedder
// repaints the window" on Linux. Dart (lib/telemetry/repaint_stats.dart)
// sends start/stop and reads the running totals once a minute; the signal
// handlers are only connected between start and stop, so it costs nothing
// while the counter is off.
//   draws:  the window's "draw" signal (GTK painted the window).
//   paints: the window's frame clock "paint" phase (a GTK frame cycle).
struct VommetRepaintCounter {
  GtkWidget* window = nullptr;
  GdkFrameClock* clock = nullptr;
  gulong draw_handler = 0;
  gulong paint_handler = 0;
  gint64 draws = 0;
  gint64 paints = 0;
};

static VommetRepaintCounter vommet_repaint_counter;

static gboolean vommet_repaint_on_draw(GtkWidget* widget, cairo_t* cr,
                                       gpointer user_data) {
  vommet_repaint_counter.draws++;
  return FALSE;
}

static void vommet_repaint_on_paint(GdkFrameClock* clock, gpointer user_data) {
  vommet_repaint_counter.paints++;
}

static void vommet_repaint_start() {
  VommetRepaintCounter& c = vommet_repaint_counter;
  if (c.draw_handler == 0) {
    c.draw_handler = g_signal_connect(c.window, "draw",
                                      G_CALLBACK(vommet_repaint_on_draw),
                                      nullptr);
  }
  if (c.paint_handler == 0) {
    GdkFrameClock* clock = gtk_widget_get_frame_clock(c.window);
    if (clock != nullptr) {
      c.clock = GDK_FRAME_CLOCK(g_object_ref(clock));
      c.paint_handler = g_signal_connect(
          clock, "paint", G_CALLBACK(vommet_repaint_on_paint), nullptr);
    }
  }
}

static void vommet_repaint_stop() {
  VommetRepaintCounter& c = vommet_repaint_counter;
  if (c.draw_handler != 0) {
    g_signal_handler_disconnect(c.window, c.draw_handler);
    c.draw_handler = 0;
  }
  if (c.paint_handler != 0) {
    g_signal_handler_disconnect(c.clock, c.paint_handler);
    c.paint_handler = 0;
    g_clear_object(&c.clock);
  }
}

static void vommet_repaint_method_cb(FlMethodChannel* channel,
                                     FlMethodCall* method_call,
                                     gpointer user_data) {
  g_autoptr(FlMethodResponse) response = nullptr;
  const gchar* name = fl_method_call_get_name(method_call);
  if (strcmp(name, "start") == 0) {
    vommet_repaint_start();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (strcmp(name, "stop") == 0) {
    vommet_repaint_stop();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (strcmp(name, "read") == 0) {
    // Running totals since the app started; Dart takes differences.
    const int64_t totals[2] = {vommet_repaint_counter.draws,
                               vommet_repaint_counter.paints};
    response = FL_METHOD_RESPONSE(
        fl_method_success_response_new(fl_value_new_int64_list(totals, 2)));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(method_call, response, nullptr);
}

// Registers the channel; it lives as long as the app.
static void vommet_repaint_counter_register(FlView* view, GtkWidget* window) {
  vommet_repaint_counter.window = window;
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  FlMethodChannel* channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "im.nether.vommet/repaint", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, vommet_repaint_method_cb,
                                            nullptr, nullptr);
}
