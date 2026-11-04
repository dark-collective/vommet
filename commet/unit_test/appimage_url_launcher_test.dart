import 'package:commet/utils/links/appimage_url_launcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const mount = "/tmp/.mount_VommetAbc123";
  const exe = "$mount/usr/lib/vommet/vommet";

  // What AppRun and the AppImage runtime leave in the environment.
  Map<String, String> appImageEnv([Map<String, String> extra = const {}]) => {
        "APPIMAGE": "/home/user/Apps/Vommet-x86_64.AppImage",
        "APPDIR": mount,
        "ARGV0": "./Vommet-x86_64.AppImage",
        "OWD": "/home/user",
        "HOME": "/home/user",
        "PATH": "/usr/local/bin:/usr/bin",
        "XDG_CURRENT_DESKTOP": "KDE",
        "LD_LIBRARY_PATH": "$mount/usr/lib/deps:$mount/usr/lib/vommet/lib",
        "XDG_DATA_DIRS": "$mount/usr/share:/usr/local/share:/usr/share",
        "GSETTINGS_SCHEMA_DIR": "$mount/usr/share/glib-2.0/schemas",
        "GIO_MODULE_DIR": "$mount/usr/lib/gio/modules",
        "GDK_PIXBUF_MODULE_FILE":
            "/home/user/.cache/vommet-appimage/loaders.cache",
        ...extra,
      };

  test("not an AppImage: no host environment", () {
    expect(
        AppImageUrlLauncher.hostEnvironmentFor(
            {"HOME": "/home/user", "LD_LIBRARY_PATH": "/opt/lib"},
            executable: "/usr/lib/vommet/vommet"),
        isNull);
  });

  test("strips everything AppRun points into the image", () {
    final env =
        AppImageUrlLauncher.hostEnvironmentFor(appImageEnv(), executable: exe)!;

    expect(env, {
      "HOME": "/home/user",
      "PATH": "/usr/local/bin:/usr/bin",
      "XDG_CURRENT_DESKTOP": "KDE",
      "XDG_DATA_DIRS": "/usr/local/share:/usr/share",
    });
  });

  test("keeps the user's own entries of a path list", () {
    final env = AppImageUrlLauncher.hostEnvironmentFor(
        appImageEnv({
          "LD_LIBRARY_PATH": "$mount/usr/lib/deps:$mount/usr/lib/vommet/lib"
              ":/opt/custom/lib",
          "XDG_DATA_DIRS":
              "$mount/usr/share:/var/lib/flatpak/exports/share:/usr/share",
        }),
        executable: exe)!;

    expect(env["LD_LIBRARY_PATH"], "/opt/custom/lib");
    expect(env["XDG_DATA_DIRS"], "/var/lib/flatpak/exports/share:/usr/share");
  });

  test("finds the image from the executable when APPDIR is missing", () {
    final env = AppImageUrlLauncher.hostEnvironmentFor(
        appImageEnv()..remove("APPDIR"),
        executable: exe)!;

    expect(env.containsKey("LD_LIBRARY_PATH"), isFalse);
    expect(env.containsKey("GIO_MODULE_DIR"), isFalse);
    expect(env["XDG_DATA_DIRS"], "/usr/local/share:/usr/share");
  });

  test("a similar but different path is kept", () {
    final env = AppImageUrlLauncher.hostEnvironmentFor(
        appImageEnv({"GIO_MODULE_DIR": "${mount}2/usr/lib/gio/modules"}),
        executable: exe)!;

    expect(env["GIO_MODULE_DIR"], "${mount}2/usr/lib/gio/modules");
  });

  test("a user's own pixbuf loader cache is kept", () {
    final env = AppImageUrlLauncher.hostEnvironmentFor(
        appImageEnv({"GDK_PIXBUF_MODULE_FILE": "/opt/gdk/loaders.cache"}),
        executable: exe)!;

    expect(env["GDK_PIXBUF_MODULE_FILE"], "/opt/gdk/loaders.cache");
  });
}
