#include "my_application.h"
#include "widget_dock.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"
#include "window_theme.h"
#include "repaint_counter.h"

#include <filesystem> 
#include <cstring>
using namespace std;
using namespace std::filesystem;

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Vommet issue 328: files copied in a file manager. The pasteboard plugin
// only asks GTK for text/uri-list, which inside the Flatpak gives host paths
// the sandbox can't open. Ask for the document portal's copy first (GTK turns
// its key into /run/user/N/doc/... paths), then the plain lists. Replies with
// {"format": target, "text": contents}; Dart parses it (file_transfer.dart).
static const char* const kVommetPortalFileTargets[] = {
    "application/vnd.portal.filetransfer",
    "application/vnd.portal.files",
};
static const char* const kVommetFileTargets[] = {
    "text/uri-list",
    "x-special/gnome-copied-files",
};

struct VommetFileRead {
  FlMethodCall* method_call;
  GPtrArray* targets;  // GdkAtom, in the order to try.
  guint next;
};

static void vommet_file_read_free(VommetFileRead* read) {
  g_object_unref(read->method_call);
  g_ptr_array_unref(read->targets);
  g_free(read);
}

static void vommet_file_read_respond(VommetFileRead* read, GdkAtom target,
                                     const gchar* text) {
  g_autoptr(FlValue) result = fl_value_new_map();
  if (text != nullptr) {
    g_autofree gchar* name = gdk_atom_name(target);
    fl_value_set_string_take(result, "format", fl_value_new_string(name));
    fl_value_set_string_take(result, "text", fl_value_new_string(text));
  }
  fl_method_call_respond_success(read->method_call, result, nullptr);
  vommet_file_read_free(read);
}

static void vommet_file_read_next(GtkClipboard* clipboard,
                                  VommetFileRead* read);

static void vommet_file_contents_cb(GtkClipboard* clipboard,
                                    GtkSelectionData* data,
                                    gpointer user_data) {
  auto* read = static_cast<VommetFileRead*>(user_data);
  GdkAtom target = static_cast<GdkAtom>(
      g_ptr_array_index(read->targets, read->next - 1));
  g_autofree gchar* name = gdk_atom_name(target);
  if (data != nullptr && gtk_selection_data_get_length(data) > 0) {
    if (g_str_has_prefix(name, "application/vnd.portal.") ||
        strcmp(name, "text/uri-list") == 0) {
      // For a portal key this calls the FileTransfer portal's RetrieveFiles.
      g_auto(GStrv) uris = gtk_selection_data_get_uris(data);
      if (uris != nullptr && uris[0] != nullptr) {
        g_autofree gchar* text = g_strjoinv("\r\n", uris);
        vommet_file_read_respond(read, gdk_atom_intern_static_string(
                                           "text/uri-list"),
                                 text);
        return;
      }
    } else {
      g_autofree gchar* text = g_strndup(
          reinterpret_cast<const gchar*>(gtk_selection_data_get_data(data)),
          gtk_selection_data_get_length(data));
      if (g_utf8_validate(text, -1, nullptr)) {
        vommet_file_read_respond(read, target, text);
        return;
      }
    }
  }
  vommet_file_read_next(clipboard, read);
}

static void vommet_file_read_next(GtkClipboard* clipboard,
                                  VommetFileRead* read) {
  if (read->next >= read->targets->len) {
    vommet_file_read_respond(read, GDK_NONE, nullptr);
    return;
  }
  GdkAtom target =
      static_cast<GdkAtom>(g_ptr_array_index(read->targets, read->next++));
  gtk_clipboard_request_contents(clipboard, target, vommet_file_contents_cb,
                                 read);
}

static void vommet_file_targets_cb(GtkClipboard* clipboard, GdkAtom* atoms,
                                   gint n_atoms, gpointer user_data) {
  auto* read = static_cast<VommetFileRead*>(user_data);
  auto offered = [&](const char* name) {
    GdkAtom atom = gdk_atom_intern(name, FALSE);
    for (gint i = 0; i < n_atoms; i++) {
      if (atoms[i] == atom) return true;
    }
    return false;
  };
  // Outside a sandbox the plain paths are readable; keep using them there.
  if (g_file_test("/.flatpak-info", G_FILE_TEST_EXISTS)) {
    for (const char* name : kVommetPortalFileTargets) {
      if (offered(name)) {
        g_ptr_array_add(read->targets, gdk_atom_intern(name, FALSE));
      }
    }
  }
  for (const char* name : kVommetFileTargets) {
    if (offered(name)) {
      g_ptr_array_add(read->targets, gdk_atom_intern(name, FALSE));
    }
  }
  vommet_file_read_next(clipboard, read);
}

static void vommet_clipboard_read_files(FlMethodCall* method_call) {
  auto* read = g_new0(VommetFileRead, 1);
  read->method_call = FL_METHOD_CALL(g_object_ref(method_call));
  read->targets = g_ptr_array_new();
  gtk_clipboard_request_targets(gtk_clipboard_get(GDK_SELECTION_CLIPBOARD),
                                vommet_file_targets_cb, read);
}

// Vommet: middle-click paste reads the primary selection (X11 and Wayland).
static void vommet_primary_text_cb(GtkClipboard* clipboard, const gchar* text,
                                   gpointer user_data) {
  g_autoptr(FlMethodCall) method_call = FL_METHOD_CALL(user_data);
  g_autoptr(FlValue) result =
      text != nullptr ? fl_value_new_string(text) : fl_value_new_null();
  fl_method_call_respond_success(method_call, result, nullptr);
}

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
  } else if (strcmp(fl_method_call_get_name(method_call), "readFiles") == 0) {
    // Answered asynchronously once the clipboard owner replies.
    vommet_clipboard_read_files(method_call);
    return;
  } else if (strcmp(fl_method_call_get_name(method_call), "setPrimary") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_STRING) {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "bad_args", "expected text", nullptr));
    } else {
      gtk_clipboard_set_text(gtk_clipboard_get(GDK_SELECTION_PRIMARY),
                             fl_value_get_string(args), -1);
      response = FL_METHOD_RESPONSE(
          fl_method_success_response_new(fl_value_new_bool(TRUE)));
    }
  } else if (strcmp(fl_method_call_get_name(method_call), "readPrimary") ==
             0) {
    // Answered asynchronously once the selection owner replies.
    gtk_clipboard_request_text(gtk_clipboard_get(GDK_SELECTION_PRIMARY),
                               vommet_primary_text_cb,
                               g_object_ref(method_call));
    return;
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(method_call, response, nullptr);
}

// Vommet issue 591: the window icon picked in Settings › Appearance, as PNG
// bytes (the window starts with the original icon above).
static void vommet_window_icon_method_cb(FlMethodChannel* channel,
                                         FlMethodCall* method_call,
                                         gpointer user_data) {
  g_autoptr(FlMethodResponse) response = nullptr;
  if (strcmp(fl_method_call_get_name(method_call), "setIcon") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    if (args == nullptr ||
        fl_value_get_type(args) != FL_VALUE_TYPE_UINT8_LIST) {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "bad_args", "expected PNG bytes", nullptr));
    } else {
      GdkPixbufLoader* loader = gdk_pixbuf_loader_new();
      gboolean written =
          gdk_pixbuf_loader_write(loader, fl_value_get_uint8_list(args),
                                  fl_value_get_length(args), nullptr);
      gboolean closed = gdk_pixbuf_loader_close(loader, nullptr);
      GdkPixbuf* pixbuf =
          (written && closed) ? gdk_pixbuf_loader_get_pixbuf(loader) : nullptr;
      if (pixbuf == nullptr) {
        response = FL_METHOD_RESPONSE(fl_method_error_response_new(
            "decode_failed", "could not decode the icon", nullptr));
      } else {
        gtk_window_set_icon(GTK_WINDOW(user_data), pixbuf);
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
  // Vommet: Flutter runs the Dart UI isolate on GTK's main thread by default,
  // so native work there (GTK, plugins) blocks the Dart event loop too.
  // VOMMET_UI_THREAD=separate gives the UI isolate its own thread, to tell
  // the two apart when diagnosing a stall. Opt-in, for testing only.
  if (g_strcmp0(g_getenv("VOMMET_UI_THREAD"), "separate") == 0) {
    fl_dart_project_set_ui_thread_policy(project, FL_UI_THREAD_POLICY_RUN_ON_SEPARATE_THREAD);
  }

  FlView* view = fl_view_new(project);
  vommet_window_theme_register(view);
  vommet_repaint_counter_register(view, GTK_WIDGET(window));
  gtk_widget_show(GTK_WIDGET(view));
  // Vommet: an overlay so docked widgets can sit above the Flutter view.
  GtkWidget* overlay = gtk_overlay_new();
  gtk_widget_show(overlay);
  gtk_container_add(GTK_CONTAINER(overlay), GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), overlay);

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));
  widget_dock_register(view, GTK_OVERLAY(overlay));

  // Vommet: clipboard channel for "Copy image" (kept for the app's lifetime).
  g_autoptr(FlStandardMethodCodec) clipboard_codec =
      fl_standard_method_codec_new();
  FlMethodChannel* clipboard_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "im.nether.vommet/clipboard", FL_METHOD_CODEC(clipboard_codec));
  fl_method_channel_set_method_call_handler(
      clipboard_channel, vommet_clipboard_method_cb, nullptr, nullptr);

  // Vommet issue 591: window icon channel (kept for the app's lifetime).
  g_autoptr(FlStandardMethodCodec) window_icon_codec =
      fl_standard_method_codec_new();
  FlMethodChannel* window_icon_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "im.nether.vommet/window_icon", FL_METHOD_CODEC(window_icon_codec));
  fl_method_channel_set_method_call_handler(
      window_icon_channel, vommet_window_icon_method_cb, window, nullptr);

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
