import 'dart:async';
import 'dart:ffi' as ffi;

import 'package:commet/config/platform_utils.dart';
import 'package:commet/debug/log.dart';
import 'package:ffi/ffi.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:uni_platform/uni_platform.dart';

/// Vommet: tells when a system wide hotkey is let go. hotkey_manager only
/// reports presses on Windows (RegisterHotKey) and Linux (keybinder), so
/// after a press this polls the key's state until it's up: GetAsyncKeyState
/// on Windows, XQueryKeymap on X11. (hotkey_manager reports releases itself
/// on macOS.)
class KeyRelease {
  static const _interval = Duration(milliseconds: 20);

  /// Whether [watch] can tell releases here (Windows, Linux on X11).
  static bool get isSupported => _windows != null || _x11 != null;

  /// Calls [onRelease] once [hotKey]'s key is up; false if it can't tell.
  static bool watch(HotKey hotKey, void Function() onRelease) {
    final isDown = _isDownFunction(hotKey);
    if (isDown == null) return false;
    Timer.periodic(_interval, (timer) {
      if (isDown()) return;
      timer.cancel();
      onRelease();
    });
    return true;
  }

  static bool Function()? _isDownFunction(HotKey hotKey) {
    final code = hotKey.physicalKey.keyCode;
    if (code == null) return null;
    if (PlatformUtils.isWindows) {
      final windows = _windows;
      if (windows == null) return null;
      return () => windows.getAsyncKeyState(code) & 0x8000 != 0;
    }
    if (PlatformUtils.isLinux) {
      final x11 = _x11;
      if (x11 == null) return null;
      final keycode = x11.keysymToKeycode(x11.display, code);
      if (keycode == 0) return null;
      return () {
        x11.queryKeymap(x11.display, x11.keys);
        return x11.keys[keycode >> 3] & (1 << (keycode & 7)) != 0;
      };
    }
    return null;
  }

  static final _Windows? _windows =
      PlatformUtils.isWindows ? _Windows.open() : null;

  static final _X11? _x11 = PlatformUtils.isLinux ? _X11.open() : null;
}

class _Windows {
  _Windows(this.getAsyncKeyState);

  final int Function(int) getAsyncKeyState;

  static _Windows? open() {
    try {
      final user32 = ffi.DynamicLibrary.open("user32.dll");
      return _Windows(user32.lookupFunction<ffi.Int16 Function(ffi.Int32),
          int Function(int)>("GetAsyncKeyState"));
    } catch (e) {
      Log.w("Push to talk: no GetAsyncKeyState: $e");
      return null;
    }
  }
}

class _X11 {
  _X11(this.display, this.keysymToKeycode, this.queryKeymap)
      : keys = calloc<ffi.Uint8>(32);

  final ffi.Pointer<ffi.Void> display;
  final int Function(ffi.Pointer<ffi.Void>, int) keysymToKeycode;
  final int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Uint8>) queryKeymap;

  /// XQueryKeymap's 256 key bits; lives as long as the app.
  final ffi.Pointer<ffi.Uint8> keys;

  /// The X server's keyboard; null on Wayland without Xwayland, where the
  /// key is only seen while Vommet is focused.
  static _X11? open() {
    try {
      final x11 = ffi.DynamicLibrary.open("libX11.so.6");
      final openDisplay = x11.lookupFunction<
          ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>),
          ffi.Pointer<ffi.Void> Function(
              ffi.Pointer<ffi.Void>)>("XOpenDisplay");
      final display = openDisplay(ffi.nullptr);
      if (display == ffi.nullptr) return null;
      return _X11(
          display,
          x11.lookupFunction<
              ffi.Uint8 Function(ffi.Pointer<ffi.Void>, ffi.UnsignedLong),
              int Function(ffi.Pointer<ffi.Void>, int)>("XKeysymToKeycode"),
          x11.lookupFunction<
              ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Uint8>),
              int Function(ffi.Pointer<ffi.Void>,
                  ffi.Pointer<ffi.Uint8>)>("XQueryKeymap"));
    } catch (e) {
      Log.w("Push to talk: no X11 keyboard: $e");
      return null;
    }
  }
}
