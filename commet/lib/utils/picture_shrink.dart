import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;

/// Vommet issue 128: when pictures are sent smaller by default. Stored in
/// the `send_smaller_pictures` preference.
enum SendSmallerMode {
  never("never"),
  mobileData("mobile"),
  always("always");

  const SendSmallerMode(this.key);
  final String key;

  static SendSmallerMode fromKey(String? key) =>
      values.firstWhere((m) => m.key == key,
          orElse: () => SendSmallerMode.mobileData);
}

/// Vommet issue 128: how small a smaller picture is (its longest side).
/// Stored in the `send_smaller_pictures_size` preference.
enum SendSmallerSize {
  small("small", 1280),
  standard("standard", 2048),
  large("large", 2560);

  const SendSmallerSize(this.key, this.longestEdge);
  final String key;
  final int longestEdge;

  static SendSmallerSize fromKey(String? key) => values
      .firstWhere((s) => s.key == key, orElse: () => SendSmallerSize.standard);
}

/// A picture re-saved smaller by [PictureShrink.shrink].
class ShrunkPicture {
  const ShrunkPicture({
    required this.data,
    required this.mimeType,
    required this.name,
    required this.width,
    required this.height,
    required this.originalWidth,
    required this.originalHeight,
    required this.originalSize,
  });

  final Uint8List data;
  final String mimeType;
  final String? name;
  final int width;
  final int height;
  final int originalWidth;
  final int originalHeight;
  final int originalSize;

  /// How much smaller it is, 0–100.
  int get percentSmaller =>
      originalSize <= 0 ? 0 : (100 - data.length * 100 / originalSize).round();
}

/// Vommet issue 128: re-saves a picture smaller before sending it, like
/// Telegram. Pure Dart (the `image` package), so it works on every platform;
/// run it off the UI thread.
class PictureShrink {
  /// JPEG quality of smaller pictures.
  static const int quality = 80;

  /// A smaller picture is only sent when it saves at least this much.
  static const double minSaving = 0.10;

  /// Whether a picture of [mimeType] can be sent smaller. GIFs keep their
  /// animation, so they're always sent as they are (animated WebP and PNG
  /// are found when decoding).
  static bool canShrink(String? mimeType) =>
      mimeType != null &&
      mimeType.startsWith("image/") &&
      mimeType != "image/gif" &&
      mimeType != "image/svg+xml";

  /// The size of a [width]×[height] picture whose longest side fits
  /// [longestEdge]. Never bigger than it was.
  static (int, int) targetSize(int width, int height, int longestEdge) {
    final longest = width > height ? width : height;
    if (longest <= longestEdge) return (width, height);
    final scale = longestEdge / longest;
    int fit(int v) {
      final r = (v * scale).round();
      return r < 1 ? 1 : r;
    }

    return (fit(width), fit(height));
  }

  /// Whether any pixel of [image] is see-through.
  static bool hasTransparency(img.Image image) {
    if (!image.hasAlpha) return false;
    for (final p in image) {
      if (p.a < p.maxChannelValue) return true;
    }
    return false;
  }

  /// [data] re-saved with its longest side at most [longestEdge]: JPEG at
  /// [quality], or PNG when it has see-through parts. Turned the right way
  /// up and without hidden info (EXIF, PNG text). Null when it can't be
  /// decoded, is animated, or wouldn't be at least [minSaving] smaller.
  static ShrunkPicture? shrink(Uint8List data,
      {required int longestEdge, String? name}) {
    final img.Image? decoded;
    try {
      decoded = img.decodeImage(data);
    } catch (_) {
      return null;
    }
    if (decoded == null || decoded.numFrames > 1) return null;

    var image = img.bakeOrientation(decoded);
    // Plain 8-bit pixels for resizing and JPEG (palette and 16-bit PNGs).
    if (image.hasPalette || image.format != img.Format.uint8) {
      image = image.convert(
          format: img.Format.uint8, numChannels: image.hasAlpha ? 4 : 3);
    }
    final originalWidth = image.width;
    final originalHeight = image.height;
    final (width, height) = targetSize(image.width, image.height, longestEdge);
    if (width != image.width || height != image.height) {
      image = img.copyResize(image,
          width: width,
          height: height,
          interpolation: img.Interpolation.average);
    }
    image.exif.clear();
    image.textData = null;

    final png = hasTransparency(image);
    final Uint8List out = png
        ? img.encodePng(image, level: 9)
        : img.encodeJpg(image, quality: quality, chroma: img.JpegChroma.yuv420);
    if (out.length > data.length * (1 - minSaving)) return null;

    final trimmed = name?.trim();
    final base = path.basenameWithoutExtension(
        trimmed == null || trimmed.isEmpty ? "picture" : trimmed);
    return ShrunkPicture(
      data: out,
      mimeType: png ? "image/png" : "image/jpeg",
      name: png ? "$base.png" : "$base.jpg",
      width: image.width,
      height: image.height,
      originalWidth: originalWidth,
      originalHeight: originalHeight,
      originalSize: data.length,
    );
  }
}
