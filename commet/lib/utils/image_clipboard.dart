import 'dart:io' show Platform;

import 'package:commet/config/platform_utils.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/utils/image_save.dart';
import 'package:flutter/foundation.dart' show Uint8List, kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:pasteboard/pasteboard.dart';

/// Vommet: "Copy image" puts a picture on the clipboard. The pasteboard
/// plugin only writes images on iOS, so Linux, Windows and Android use our
/// own channel (linux/my_application.cc, windows/runner/flutter_window.cpp,
/// android .../VommetClipboard.kt).
class ImageClipboard {
  static const _channel = MethodChannel("im.nether.vommet/clipboard");

  static bool get _isIOS => !kIsWeb && Platform.isIOS;

  static bool get supported =>
      PlatformUtils.isLinux ||
      PlatformUtils.isWindows ||
      PlatformUtils.isAndroid ||
      _isIOS;

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
