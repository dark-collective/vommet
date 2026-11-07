// Vommet: opens a widget as its own top-level page instead of inside the
// widget frame. For catalog widgets marked "direct" (Drawpile's browser app
// needs a cross-origin-isolated page, which no iframe gets). These widgets
// don't use the widget API, so no runner or transport is set up.
import 'package:url_launcher/url_launcher.dart';

class MatrixWidgetDirectLaunch {
  /// In the default browser (no build needs Chromium; the Flatpak goes
  /// through the desktop's open-URL portal).
  static Future<void> open(String url) async {
    final uri = openableUri(url);
    if (uri == null) {
      throw Exception("Only https widgets can open directly");
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
}
