#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

#include <filesystem> 
#include <cstring>
using namespace std;
using namespace std::filesystem;

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Vommet: "Copy image". The pasteboard plugin only writes images on iOS, so
// put the PNG on the GTK clipboard ourselves.
static void vommet_clipboard_method_cb(FlMethodChannel* channel,
                                       FlMethodCall* method_call,
                                       gpointer user_data) {
  g_autoptr(FlMethodResponse) response = nullptr;
  if (strcmp(fl_method_call_get_name(method_call), "writeImage") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    if (args == nullptr ||
        fl_value_get_type(args) != FL_VALUE_TYPE_UINT8_LIST) {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "bad_args", "expected PNG bytes", nullptr));
    } else {
      GdkPixbufLoader* loader = gdk_pixbuf_loader_new();
      g_autoptr(GError) error = nullptr;
      gboolean written =
          gdk_pixbuf_loader_write(loader, fl_value_get_uint8_list(args),
                                  fl_value_get_length(args), &error);
      gboolean closed = gdk_pixbuf_loader_close(loader, nullptr);
      GdkPixbuf* pixbuf =
          (written && closed) ? gdk_pixbuf_loader_get_pixbuf(loader) : nullptr;
      if (pixbuf == nullptr) {
        response = FL_METHOD_RESPONSE(fl_method_error_response_new(
            "decode_failed", "could not decode the image", nullptr));
      } else {
        GtkClipboard* clipboard = gtk_clipboard_get(GDK_SELECTION_CLIPBOARD);
        gtk_clipboard_set_image(clipboard, pixbuf);
        gtk_clipboard_store(clipboard);
        response = FL_METHOD_RESPONSE(
            fl_method_success_response_new(fl_value_new_bool(TRUE)));
      }
      g_object_unref(loader);
    }
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(method_call, response, nullptr);
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);


  GList* windows = gtk_application_get_windows(GTK_APPLICATION(application));

  if (windows) {
    gtk_window_present(GTK_WINDOW(windows->data));
    return;
  }

  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  
  gtk_window_set_title(window, "Vommet");
  
  const string iconFilename = "assets/images/app_icon/app_icon_rounded.png";
  path execDir = canonical(read_symlink("/proc/self/exe")).parent_path();
  path iconPath = execDir / "data/flutter_assets" / iconFilename;
  gtk_window_set_icon_from_file(GTK_WINDOW(window), iconPath.c_str(), NULL);

  gtk_window_set_default_size(window, 1280, 720);
  gtk_widget_show(GTK_WIDGET(window));

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  // Vommet: clipboard channel for "Copy image" (kept for the app's lifetime).
  g_autoptr(FlStandardMethodCodec) clipboard_codec =
      fl_standard_method_codec_new();
  FlMethodChannel* clipboard_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "im.nether.vommet/clipboard", FL_METHOD_CODEC(clipboard_codec));
  fl_method_channel_set_method_call_handler(
      clipboard_channel, vommet_clipboard_method_cb, nullptr, nullptr);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application, gchar*** arguments, int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
     g_warning("Failed to register: %s", error->message);
     *exit_status = 1;
     return TRUE;
  }

  g_application_activate(application);
  
  *exit_status = 0;

  return FALSE;
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line = my_application_local_command_line;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);



  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID,
                                     "flags", G_APPLICATION_HANDLES_COMMAND_LINE | G_APPLICATION_HANDLES_OPEN,
                                     nullptr));
}
