import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/painting.dart';
// ignore: depend_on_referenced_packages
import 'package:material_color_utilities/material_color_utilities.dart';

/// Vommet: the seed colour that `ColorScheme.fromImageProvider` derives from
/// an image, with the expensive part (colour clustering and scoring) in a
/// background isolate. `ColorScheme.fromImageProvider` does it all on the
/// UI isolate: about 1 s of UI-isolate time for 23 space avatars on a
/// desktop (startup CPU profile, 2026-10-12), more on a phone.
///
/// Same steps as Flutter's implementation: scale the image to fit 112 px,
/// quantize its pixels to 128 colours (Celebi), score them, take the best.
/// `ColorScheme.fromSeed` with the same variant then gives the same scheme.
class ImageSeedColor {
  static const _maxDimension = 112;

  /// The seed colour of [provider]'s image, or null if it can't be loaded
  /// or has no usable colours.
  static Future<Color?> fromProvider(ImageProvider provider) async {
    final image = await _scaled(provider);
    if (image == null) return null;
    final bytes = await image.toByteData();
    image.dispose();
    if (bytes == null) return null;
    final pixels = Uint32List.fromList(bytes.buffer.asUint32List());
    final argb = await Isolate.run(() => seedFromAbgrPixels(pixels));
    return argb == null ? null : Color(argb);
  }

  /// The scoring step on raw pixels as `toByteData()` lays them out (RGBA
  /// bytes read as little-endian 32-bit words, i.e. ABGR). Runs anywhere;
  /// public for tests.
  static Future<int?> seedFromAbgrPixels(Uint32List pixels) async {
    final result = await QuantizerCelebi()
        .quantize(pixels, 128, returnInputPixelToClusterPixel: true);
    final colorToCount = result.colorToCount
        .map((abgr, count) => MapEntry(_argbFromAbgr(abgr), count));
    final scored = Score.score(colorToCount, desired: 1);
    return scored.isEmpty ? null : scored.first;
  }

  static int _argbFromAbgr(int abgr) {
    final a = (abgr >> 24) & 0xff;
    final b = (abgr >> 16) & 0xff;
    final g = (abgr >> 8) & 0xff;
    final r = abgr & 0xff;
    return (a << 24) | (r << 16) | (g << 8) | b;
  }

  static Future<ui.Image?> _scaled(ImageProvider provider) async {
    final stream = provider.resolve(ImageConfiguration.empty);
    final completer = Completer<ui.Image?>();
    late final ImageStreamListener listener;
    listener = ImageStreamListener((info, _) {
      if (!completer.isCompleted) completer.complete(info.image.clone());
      info.dispose();
      stream.removeListener(listener);
    }, onError: (_, __) {
      if (!completer.isCompleted) completer.complete(null);
      stream.removeListener(listener);
    });
    stream.addListener(listener);
    final image = await completer.future;
    if (image == null) return null;

    final width = image.width;
    final height = image.height;
    final small = width <= _maxDimension && height <= _maxDimension;
    // Vommet: on the web a small image is still redrawn: outside Chromium
    // the decoded image is backed by an <img> element, and reading its
    // pixels back failed in Firefox ("IndexSizeError"), logged as an error
    // for every space avatar thumbnail.
    if (small && !kIsWeb) return image;
    final scale =
        small ? 1.0 : _maxDimension / (width > height ? width : height);
    final w = (width * scale).round().clamp(1, _maxDimension);
    final h = (height * scale).round().clamp(1, _maxDimension);
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawImageRect(
      image,
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..filterQuality = FilterQuality.none,
    );
    final picture = recorder.endRecording();
    final scaled = await picture.toImage(w, h);
    picture.dispose();
    image.dispose();
    return scaled;
  }
}
