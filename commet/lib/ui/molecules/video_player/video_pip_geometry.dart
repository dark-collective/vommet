import 'dart:math';

import 'package:flutter/painting.dart';

/// Vommet: where the picture-in-picture window sits. It docks in one of the
/// four corners of the app window; dragging it lets it go anywhere and it
/// snaps to the nearest corner when let go.
class VideoPipGeometry {
  static const double margin = 16;
  static const double minWidth = 200;
  static const double maxWidth = 720;
  static const double defaultWidth = 320;

  /// Height of the window's top bar (drag handle and buttons).
  static const double barHeight = 32;

  /// The corner nearest to [center] in a [screen]-sized area.
  static Alignment nearestCorner(Offset center, Size screen) {
    final right = center.dx > screen.width / 2;
    final bottom = center.dy > screen.height / 2;
    return Alignment(right ? 1 : -1, bottom ? 1 : -1);
  }

  /// [width] kept between [minWidth] and what fits in [screen].
  static double clampWidth(double width, Size screen, double aspectRatio) {
    final fitsWide = screen.width - margin * 2;
    final fitsTall = (screen.height - margin * 2 - barHeight) * aspectRatio;
    // On a very small window the minimum gives way to what fits.
    final upper = max(1.0, min(maxWidth, min(fitsWide, fitsTall)));
    return width.clamp(min(minWidth, upper), upper);
  }

  /// The video's aspect ratio, kept sane (unknown or odd sizes → 16:9).
  static double safeAspectRatio(double? aspectRatio) {
    if (aspectRatio == null || !aspectRatio.isFinite || aspectRatio <= 0) {
      return 16 / 9;
    }
    return aspectRatio.clamp(0.4, 3.0);
  }

  /// Size of the whole window (top bar + video).
  static Size windowSize(double width, double aspectRatio) =>
      Size(width, width / aspectRatio + barHeight);

  /// Top-left of a [window]-sized box docked in [corner] of [screen],
  /// [margin] away from the edges plus the [padding] (system bars).
  static Offset dockedOffset(Alignment corner, Size window, Size screen,
      {EdgeInsets padding = EdgeInsets.zero}) {
    final left = corner.x < 0
        ? padding.left + margin
        : screen.width - padding.right - margin - window.width;
    final top = corner.y < 0
        ? padding.top + margin
        : screen.height - padding.bottom - margin - window.height;
    return Offset(max(0, left), max(0, top));
  }
}
