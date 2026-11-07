// Vommet: still-photo overlay loading, without freezing animated assets (issue 1056).
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:commet/client/components/emoticon/emoticon.dart';
import 'package:commet/client/matrix/matrix_mxc_image_provider.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart' show Intl;

class PhotoOverlayAsset {
  static String get unsupported =>
      Intl.message("This format isn't supported in photo edits.",
          name: 'photoOverlayUnsupported');
  static String get animated =>
      Intl.message("Animated stickers aren't supported in photo edits yet.",
          name: 'photoOverlayAnimated');
  static String get failed =>
      Intl.message("Couldn't load this overlay. Try again or choose another.",
          name: 'photoOverlayFailed');

  // Inspect encoded frames too: browser image decoders may expose one frame.
  static bool isStill(Uint8List bytes) {
    try {
      return _isStill(bytes);
    } catch (_) {
      throw FormatException(unsupported);
    }
  }

  static bool _isStill(Uint8List bytes) {
    final decoder = img.findDecoderForData(bytes);
    if (decoder is! img.PngDecoder &&
        decoder is! img.WebPDecoder &&
        decoder is! img.JpegDecoder) {
      throw FormatException(unsupported);
    }
    final info = decoder!.startDecode(bytes);
    if (info == null) throw FormatException(unsupported);
    return info is img.WebPInfo ? !info.hasAnimation : info.numFrames == 1;
  }

  static Future<ui.Image> decode(Uint8List bytes) async {
    if (!isStill(bytes)) throw FormatException(animated);
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      if (codec.frameCount != 1) throw FormatException(animated);
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  }

  static Future<ui.Image> load(Emoticon emoticon) async {
    if (emoticon.image == null) {
      final painter = TextPainter(
          text: TextSpan(
              text: emoticon.slug,
              style: const TextStyle(fontFamily: 'EmojiFont', fontSize: 1024)),
          textDirection: TextDirection.ltr)
        ..layout();
      final recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder), Offset.zero);
      final picture = recorder.endRecording();
      try {
        return await picture.toImage(painter.width.ceil().clamp(1, 4096),
            painter.height.ceil().clamp(1, 4096));
      } finally {
        picture.dispose();
        painter.dispose();
      }
    }
    final provider = emoticon.image;
    // Original bytes, not the picker's 100/512px decoded preview.
    if (provider is! MatrixMxcImage) throw FormatException(unsupported);
    final bytes = await MatrixMxcImage.loadMatrixFullRes(
        provider.client, provider.identifier, null);
    if (bytes == null) throw FormatException(failed);
    return decode(bytes);
  }
}
