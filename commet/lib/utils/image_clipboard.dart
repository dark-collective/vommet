import 'dart:io' show Platform;

import 'package:commet/config/platform_utils.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/utils/image_save.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
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
}
