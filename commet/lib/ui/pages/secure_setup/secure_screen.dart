import 'package:commet/config/platform_utils.dart';
import 'package:commet/debug/log.dart';
import 'package:flutter/services.dart';

/// Vommet issue 129: Android-only helpers for the secure messaging setup.
/// Elsewhere they do nothing (desktop screenshots can't be blocked; Apple's
/// password manager is end-to-end encrypted).
class SecureScreen {
  static const _channel = MethodChannel("im.nether.chat/secure_screen");

  /// Block screenshots and screen recording (and the app switcher preview)
  /// while a recovery key is on screen.
  static Future<void> setSecure(bool on) async {
    if (!PlatformUtils.isAndroid) return;
    try {
      await _channel.invokeMethod("setSecure", {"on": on});
    } catch (e) {
      Log.w("Couldn't change screenshot blocking: $e");
    }
  }

  /// The package of the system autofill service, when Android says.
  static Future<String?> autofillService() async {
    if (!PlatformUtils.isAndroid) return null;
    try {
      return await _channel.invokeMethod<String>("autofillService");
    } catch (_) {
      return null;
    }
  }

  /// Google Password Manager is the autofill service: only end-to-end
  /// encrypted with on-device encryption on, so the UI says so.
  static Future<bool> autofillIsGoogle() async =>
      await autofillService() == "com.google.android.gms";
}
