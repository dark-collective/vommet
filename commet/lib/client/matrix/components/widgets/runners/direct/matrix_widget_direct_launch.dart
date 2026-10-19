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
    if (PlatformUtils.isLinux && !BuildConfig.IS_FLATPAK) {
      final browser = await _findChromium();
      if (browser != null) {
        final temp = await getTemporaryDirectory();
        final profile = p.join(temp.path, "im.nether.chat", "widget_direct");
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

    if (!await launchUrl(Uri.parse(url),
        mode: LaunchMode.externalApplication)) {
      throw Exception("Could not open the widget in a browser");
    }
  }

  static Future<String?> _findChromium() async {
    for (final name in ["chromium", "chromium-browser", "google-chrome"]) {
      final result = await SystemProcessesUtils.runSubprocess("which", [name]);
      if (result.exitCode == 0) return name;
    }
    return null;
  }
}
