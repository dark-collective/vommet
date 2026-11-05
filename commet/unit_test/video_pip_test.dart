import 'package:commet/ui/molecules/video_player/video_pip_geometry.dart';
import 'package:flutter/painting.dart';
import 'package:test/test.dart';

void main() {
  const screen = Size(1200, 800);

  test('snaps to the nearest corner', () {
    expect(VideoPipGeometry.nearestCorner(const Offset(100, 100), screen),
        Alignment.topLeft);
    expect(VideoPipGeometry.nearestCorner(const Offset(1100, 100), screen),
        Alignment.topRight);
    expect(VideoPipGeometry.nearestCorner(const Offset(100, 700), screen),
        Alignment.bottomLeft);
    expect(VideoPipGeometry.nearestCorner(const Offset(1100, 700), screen),
        Alignment.bottomRight);
  });

  test('width stays between the minimum and what fits', () {
    expect(VideoPipGeometry.clampWidth(50, screen, 16 / 9),
        VideoPipGeometry.minWidth);
    expect(VideoPipGeometry.clampWidth(5000, screen, 16 / 9),
        VideoPipGeometry.maxWidth);
    expect(VideoPipGeometry.clampWidth(400, screen, 16 / 9), 400);
    // A tall video on a short window: limited by the height.
    final tall = VideoPipGeometry.clampWidth(700, const Size(1200, 400), 0.5);
    expect(tall, closeTo((400 - 32 - VideoPipGeometry.barHeight) * 0.5, 0.001));
    // A phone narrower than the minimum still fits.
    expect(VideoPipGeometry.clampWidth(300, const Size(180, 600), 16 / 9),
        lessThanOrEqualTo(180));
  });

  test('odd aspect ratios fall back or are kept sane', () {
    expect(VideoPipGeometry.safeAspectRatio(null), 16 / 9);
    expect(VideoPipGeometry.safeAspectRatio(0), 16 / 9);
    expect(VideoPipGeometry.safeAspectRatio(double.nan), 16 / 9);
    expect(VideoPipGeometry.safeAspectRatio(10), 3.0);
    expect(VideoPipGeometry.safeAspectRatio(1.5), 1.5);
  });

  test('docked offset keeps the margin and the system bars', () {
    final window = VideoPipGeometry.windowSize(320, 16 / 9);
    expect(window.height, 180 + VideoPipGeometry.barHeight);
    expect(
        VideoPipGeometry.dockedOffset(Alignment.topLeft, window, screen,
            padding: const EdgeInsets.only(top: 24)),
        const Offset(16, 40));
    expect(VideoPipGeometry.dockedOffset(Alignment.bottomRight, window, screen),
        Offset(1200 - 16 - 320, 800 - 16 - window.height));
  });
}
