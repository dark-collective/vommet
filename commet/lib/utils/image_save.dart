import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:commet/utils/download_utils.dart';
import 'package:commet/utils/image/lod_image.dart';
import 'package:commet/utils/mime.dart';
import 'package:flutter/widgets.dart';

/// Vommet: get the bytes of any image Vommet shows (attachments, avatars,
/// banners) so it can be saved or copied. Matrix images give the original
/// full-size file (from the cache, decrypted when needed); anything else is
/// encoded as PNG.
class ImageSave {
  /// Bytes and a file extension (without the dot), or null if the image
  /// can't be loaded.
  static Future<(Uint8List, String)?> bytesOf(ImageProvider image) async {
    if (image is LODImageProvider && image.loadFullRes != null) {
      try {
        final bytes = await image.loadFullRes!.call();
        if (bytes != null && bytes.isNotEmpty) {
          final mime = Mime.lookupType("", data: bytes);
          final ext = mime == null ? null : Mime.extensionFromMime(mime);
          return (bytes, ext ?? "png");
        }
      } catch (_) {
        // Fall back to the decoded picture below.
      }
    }

    final decoded = await _decode(image);
    if (decoded == null) return null;
    final png = await decoded.toByteData(format: ui.ImageByteFormat.png);
    if (png == null) return null;
    return (png.buffer.asUint8List(), "png");
  }

  /// [image] as PNG bytes (what clipboards take): the original when it's
  /// already PNG, else its first frame re-encoded.
  static Future<Uint8List?> pngOf(ImageProvider image) async {
    final result = await bytesOf(image);
    if (result == null) return null;
    final (bytes, ext) = result;
    if (ext == "png") return bytes;
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      return png?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  /// Opens a "Save as" dialog for [image]. [fileName] is the suggested name;
  /// without one, "image.<ext>".
  static Future<bool> saveAs(ImageProvider image, {String? fileName}) async {
    final result = await bytesOf(image);
    if (result == null) return false;
    final (bytes, ext) = result;
    var name = fileName ?? "image.$ext";
    if (!name.contains(".")) name = "$name.$ext";
    return DownloadUtils.saveBytes(bytes, name);
  }

  static Future<ui.Image?> _decode(ImageProvider image) {
    final completer = Completer<ui.Image?>();
    final stream = image.resolve(const ImageConfiguration());
    late ImageStreamListener listener;
    listener = ImageStreamListener((info, _) {
      if (!completer.isCompleted) completer.complete(info.image);
      stream.removeListener(listener);
    }, onError: (_, __) {
      if (!completer.isCompleted) completer.complete(null);
      stream.removeListener(listener);
    });
    stream.addListener(listener);
    return completer.future;
  }
}
