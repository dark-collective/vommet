import 'package:hotkey_manager/hotkey_manager.dart';

/// Vommet: web stand-in for key_release_native.dart (no system wide hotkeys
/// in the browser).
class KeyRelease {
  static bool get isSupported => false;

  static bool watch(HotKey hotKey, void Function() onRelease) => false;
}
