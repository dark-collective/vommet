// Vommet: opens a widget as its own top-level page instead of inside the
// widget frame. For catalog widgets marked "direct" (Drawpile's browser app
// needs a cross-origin-isolated page, which no iframe gets). These widgets
// don't use the widget API, so no runner or transport is set up.
import 'dart:io';

import 'package:commet/config/build_config.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/utils/system_processes_utils.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

class MatrixWidgetDirectLaunch {
  /// On Linux, a Chromium app window (no address bar), with its own profile
  /// so the widget's settings stick. Otherwise, the default browser.
  static Future<void> open(String url) async {
    final uri = openableUri(url);
    if (uri == null) {
      throw Exception("Only https widgets can open directly");
    }

    if (PlatformUtils.isLinux && !BuildConfig.IS_FLATPAK) {
      final browser = await _findChromium();
      if (browser != null) {
        // Not under /tmp: other local users could create or read it there.
        final support = await getApplicationSupportDirectory();
        final profile = p.join(support.path, "widget_direct");
        Log.i("Opening widget directly in $browser");
        await Process.start(browser, [
          '--app=$url',
          '--no-first-run',
          '--no-default-browser-check',
          '--user-data-dir=$profile',
        ]);
        return;
      }
    }

    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw Exception("Could not open the widget in a browser");
    }
  }

  /// [url] as a Uri if it may be opened: the URL comes from room state, so
  /// only https pages go to the browser or the OS, never another scheme
  /// some local app would handle.
  static Uri? openableUri(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != "https" || uri.host.isEmpty) return null;
    return uri;
  }

  static Future<String?> _findChromium() async {
    for (final name in ["chromium", "chromium-browser", "google-chrome"]) {
      final result = await SystemProcessesUtils.runSubprocess("which", [name]);
      if (result.exitCode == 0) return name;
    }
    return null;
  }
}
