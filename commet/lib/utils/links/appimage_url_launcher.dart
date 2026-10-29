import 'dart:async';
import 'dart:io';

import 'package:commet/debug/log.dart';
import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

/// Vommet issue 768: inside the AppImage, links opened through url_launcher
/// did nothing. AppRun points LD_LIBRARY_PATH, XDG_DATA_DIRS, GIO_MODULE_DIR,
/// GSETTINGS_SCHEMA_DIR and GDK_PIXBUF_MODULE_FILE at the AppImage's own
/// libraries, and GIO passes all of that on to the browser it starts. Here
/// links go to the host's `xdg-open` with those values taken out (the host
/// tools then pick the browser, e.g. kde-open on KDE), and to the desktop's
/// OpenURI portal if that fails. Outside an AppImage nothing changes.
class AppImageUrlLauncher extends UrlLauncherPlatform {
  AppImageUrlLauncher(this.inner, this.hostEnvironment);

  final UrlLauncherPlatform inner;
  final Map<String, String> hostEnvironment;

  /// Wraps the platform launcher when the app runs from an AppImage.
  /// Not on web, where dart:io's Platform throws: that stopped startup before
  /// the emoji data loaded, and every chat then failed to build (a gray block
  /// instead of the timeline and composer, Vommet issue 809).
  static void installIfAppImage() {
    if (kIsWeb || !Platform.isLinux) return;

    final env = hostEnvironmentFor(Platform.environment,
        executable: Platform.resolvedExecutable);
    if (env == null) return;

    UrlLauncherPlatform.instance =
        AppImageUrlLauncher(UrlLauncherPlatform.instance, env);
  }

  /// The parts of the AppImage's own environment that must not reach other
  /// programs: AppRun's variables, plus anything else that points into the
  /// mounted image. Null when not running from an AppImage.
  static Map<String, String>? hostEnvironmentFor(Map<String, String> env,
      {String? executable}) {
    final appImage = env["APPIMAGE"];
    if (appImage == null || appImage.isEmpty) return null;

    final roots = <String>{};
    final appDir = env["APPDIR"];
    if (appDir != null && appDir.isNotEmpty) roots.add(_trimSlash(appDir));

    // AppRun lives at the image root; the binary at usr/lib/vommet/vommet.
    const binary = "/usr/lib/vommet/vommet";
    if (executable != null && executable.endsWith(binary)) {
      roots.add(executable.substring(0, executable.length - binary.length));
    }
    roots.removeWhere((root) => root.isEmpty);

    bool inImage(String path) =>
        roots.any((root) => path == root || path.startsWith("$root/"));

    final result = <String, String>{};
    for (final entry in env.entries) {
      final key = entry.key;
      final value = entry.value;

      if (_runtimeOnly.contains(key)) continue;

      // AppRun writes this loader cache (listing loaders inside the image)
      // under the user's cache directory.
      if (key == "GDK_PIXBUF_MODULE_FILE" &&
          (inImage(value) || value.contains("/vommet-appimage/"))) {
        continue;
      }

      if (!roots.any((root) => value.contains(root))) {
        result[key] = value;
        continue;
      }

      final parts = value.split(":");
      final kept = parts.where((part) => !inImage(part)).toList();
      if (kept.length == parts.length) {
        result[key] = value;
      } else if (kept.any((part) => part.isNotEmpty)) {
        result[key] = kept.join(":");
      }
    }

    return result;
  }

  /// Set by the AppImage runtime for this app only.
  static const _runtimeOnly = {"APPIMAGE", "APPDIR", "ARGV0", "OWD"};

  static String _trimSlash(String path) => path.length > 1 && path.endsWith("/")
      ? path.substring(0, path.length - 1)
      : path;

  Future<bool> _open(String url) async {
    if (await _xdgOpen(url)) return true;
    if (await _portalOpen(url)) return true;
    return false;
  }

  Future<bool> _xdgOpen(String url) async {
    try {
      final process = await Process.start("xdg-open", [url],
          environment: hostEnvironment,
          includeParentEnvironment: false,
          // AppRun cds into the image; don't leave the browser there.
          workingDirectory: hostEnvironment["HOME"]);

      final stderr = StringBuffer();
      process.stdout.drain<void>();
      process.stderr
          .transform(const SystemEncoding().decoder)
          .listen(stderr.write);

      // xdg-open can wait for a browser it starts directly; still running
      // after a few seconds means the browser is up.
      final code = await process.exitCode
          .timeout(const Duration(seconds: 5), onTimeout: () => 0);
      if (code == 0) return true;

      Log.w("xdg-open exited with $code: ${stderr.toString().trim()}");
    } catch (e) {
      Log.w("Could not run xdg-open: $e");
    }
    return false;
  }

  Future<bool> _portalOpen(String url) async {
    final client = DBusClient.session();
    try {
      await client.callMethod(
          destination: "org.freedesktop.portal.Desktop",
          path: DBusObjectPath("/org/freedesktop/portal/desktop"),
          interface: "org.freedesktop.portal.OpenURI",
          name: "OpenURI",
          values: [DBusString(""), DBusString(url), DBusDict.stringVariant({})],
          replySignature: DBusSignature("o"));
      return true;
    } catch (e) {
      Log.w("OpenURI portal failed: $e");
      return false;
    } finally {
      await client.close();
    }
  }

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    if (await _open(url)) return true;
    return inner.launchUrl(url, options);
  }

  @override
  Future<bool> launch(
    String url, {
    required bool useSafariVC,
    required bool useWebView,
    required bool enableJavaScript,
    required bool enableDomStorage,
    required bool universalLinksOnly,
    required Map<String, String> headers,
    String? webOnlyWindowName,
  }) async {
    if (await _open(url)) return true;
    return inner.launch(url,
        useSafariVC: useSafariVC,
        useWebView: useWebView,
        enableJavaScript: enableJavaScript,
        enableDomStorage: enableDomStorage,
        universalLinksOnly: universalLinksOnly,
        headers: headers,
        webOnlyWindowName: webOnlyWindowName);
  }

  @override
  LinkDelegate? get linkDelegate => inner.linkDelegate;

  @override
  Future<bool> canLaunch(String url) => inner.canLaunch(url);

  @override
  Future<void> closeWebView() => inner.closeWebView();

  @override
  Future<bool> supportsMode(PreferredLaunchMode mode) =>
      inner.supportsMode(mode);

  @override
  Future<bool> supportsCloseForMode(PreferredLaunchMode mode) =>
      inner.supportsCloseForMode(mode);
}
