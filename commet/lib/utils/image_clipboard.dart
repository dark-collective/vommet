import 'package:commet/config/platform_utils.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/utils/image_save.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:pasteboard/pasteboard.dart';

/// Vommet: "Copy image" puts a picture on the clipboard. The pasteboard
/// plugin only writes images on iOS, so Linux, Windows and Android use our
/// own channel (linux/my_application.cc, windows/runner/flutter_window.cpp,
/// android .../VommetClipboard.kt).
class ImageClipboard {
  static const _channel = MethodChannel("im.nether.vommet/clipboard");

  static bool get _isIOS => PlatformUtils.isIOS;

  static bool get supported =>
      PlatformUtils.isLinux ||
      PlatformUtils.isWindows ||
      PlatformUtils.isAndroid ||
      _isIOS;

  static final List<void Function(Uint8List? data)> _pasteListeners = [];
  static Future<void> _handleNativePaste(MethodCall call) async {
    if (call.method != "pasteImage") return;
    final raw = call.arguments;
    final Uint8List? data = raw is Uint8List
        ? raw
        : (raw is List<int> ? Uint8List.fromList(raw) : null);
    for (final listener in List.of(_pasteListeners)) {
      listener(data);
    }
  }

  /// Vommet issue 1113: on iPadOS, the on-screen keyboard's paste button
  /// invokes UIKit's paste action, which forwards image-only clipboard data.
  static void Function() listenForPaste(
      void Function(Uint8List? data) onPaste) {
    if (_pasteListeners.isEmpty) {
      _channel.setMethodCallHandler(_handleNativePaste);
    }
    _pasteListeners.add(onPaste);
    return () {
      if (_pasteListeners.remove(onPaste) && _pasteListeners.isEmpty) {
        _channel.setMethodCallHandler(null);
      }
    };
  }

  /// True when the image is on the clipboard.
  static Future<bool> copy(ImageProvider image) async {
    if (!supported) return false;
    final png = await ImageSave.pngOf(image);
    if (png == null) return false;
    try {
      if (_isIOS) {
        await Pasteboard.writeImage(png);
        return true;
      }
      return await _channel.invokeMethod<bool>("writeImage", png) == true;
    } catch (e, s) {
      Log.onError(e, s, content: "Copy image failed");
      return false;
    }
  }

  /// The image on the clipboard, or null. Android reads through our
  /// channel (the pasteboard plugin has no Android code). Windows reads a
  /// PNG through our channel first (the plugin can't read the image
  /// "Copy image" writes, Vommet issue 484), then falls back to the plugin.
  /// The other platforms use the plugin.
  static Future<Uint8List?> read() async {
    try {
      if (PlatformUtils.isAndroid) {
        return await _channel.invokeMethod<Uint8List>("readImage");
      }
      if (PlatformUtils.isWindows) {
        final png = await _channel.invokeMethod<Uint8List>("readImage");
        if (png != null && png.isNotEmpty) return png;
      }
      return await Pasteboard.image;
    } catch (e, s) {
      Log.onError(e, s, content: "Paste image failed");
      return null;
    }
  }
}
