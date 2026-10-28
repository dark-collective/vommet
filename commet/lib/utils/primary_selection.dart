import 'package:commet/config/platform_utils.dart';
import 'package:flutter/services.dart';

/// Vommet: the Linux primary selection (X11 and Wayland). Selecting text puts
/// it here and middle-click pastes it, as in other Linux apps. Flutter's
/// clipboard API only covers the regular clipboard, so this goes through our
/// own channel (linux/my_application.cc). Does nothing on other platforms.
class PrimarySelection {
  static const _channel = MethodChannel("im.nether.vommet/clipboard");

  static bool get supported => PlatformUtils.isLinux;

  /// Puts [text] on the primary selection.
  static void set(String? text) {
    if (!supported || text == null || text.isEmpty) return;
    _channel.invokeMethod("setPrimary", text).catchError((_) => null);
  }

  /// The primary selection's text, or null when it holds none.
  static Future<String?> read() async {
    if (!supported) return null;
    try {
      return await _channel.invokeMethod<String>("readPrimary");
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
