import 'dart:math';

/// Vommet: limits for decoding a full-size image, applied to both sides at
/// once so the aspect ratio is kept.
///
/// Capping only the height (as upstream did on Linux, to avoid a decode
/// flicker with very large images) squashes tall images: an 800x19600
/// screenshot decoded at height 1440 is 59 px wide and unreadable. Capping the
/// total pixel count and the longest side instead keeps the decode cost
/// bounded without singling out one axis.
class ImageDecodeLimits {
  const ImageDecodeLimits({this.maxPixels, this.maxSide});

  /// Largest decoded width x height.
  final int? maxPixels;

  /// Largest decoded width or height. GPUs cannot upload textures past their
  /// maximum texture size; 16384 is the minimum OpenGL 4.x guarantees.
  final int? maxSide;

  /// Inline timeline images on Linux: about as many pixels as upstream's
  /// 1440 px height cap allowed for a 4:3 photo.
  static const linuxTimeline =
      ImageDecodeLimits(maxPixels: 1920 * 1440, maxSide: 16384);

  /// The image viewer on Linux, opened on purpose, so it can afford a much
  /// bigger decode to stay sharp when zoomed.
  static const linuxViewer =
      ImageDecodeLimits(maxPixels: 4096 * 4096, maxSide: 16384);

  /// The size to decode an image of [width] x [height] at, or null to decode
  /// at its own size. Never scales up.
  ({int width, int height})? fit(int width, int height) {
    if (width <= 0 || height <= 0) return null;

    var scale = 1.0;
    if (maxPixels != null && width * height > maxPixels!) {
      scale = sqrt(maxPixels! / (width * height));
    }
    if (maxSide != null) {
      scale = min(scale, maxSide! / max(width, height));
    }
    if (scale >= 1) return null;

    return (
      width: max(1, (width * scale).floor()),
      height: max(1, (height * scale).floor()),
    );
  }
}
