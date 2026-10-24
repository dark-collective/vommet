import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Vommet: a small glyph beside an avatar's bottom-right corner instead of
/// on top of it, so it marks a room type (headphones on voice rooms) without
/// covering the room's picture. Optionally a thin ring around the avatar,
/// open where the glyph sits ([color]; null for no ring).
class AvatarRing extends StatelessWidget {
  const AvatarRing({
    super.key,
    required this.child,
    required this.size,
    this.color,
    this.glyph,
    this.glyphColor,
  });

  /// The avatar, at most [size] - 8 across (2 px ring + 2 px gap each side).
  final Widget child;

  /// Outer diameter of the ring.
  final double size;

  final Color? color;

  final IconData? glyph;

  /// Defaults to [color].
  final Color? glyphColor;

  /// Room the avatar gets inside [size]: 2 px ring + 2 px gap each side
  /// with a ring; without one, nearly full size (the glyph sits further out).
  static double innerSize(double size, {bool ring = true}) =>
      size - (ring ? 8 : 4);

  @override
  Widget build(BuildContext context) {
    final glyphSize = (size * 0.42).roundToDouble().clamp(10.0, 14.0);
    final inset = color == null ? 2.0 : 4.0;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (color != null)
            Positioned.fill(
              child: CustomPaint(
                  painter: _OpenRing(color!, gap: glyph == null ? 0 : 1.24)),
            ),
          Positioned(
              left: inset,
              top: inset,
              right: inset,
              bottom: inset,
              child: child),
          if (glyph != null)
            Positioned(
              right: color == null ? -glyphSize * 0.45 : -glyphSize / 3,
              bottom: color == null ? -glyphSize * 0.45 : -glyphSize / 3,
              child: Icon(glyph, size: glyphSize, color: glyphColor ?? color),
            ),
        ],
      ),
    );
  }
}

class _OpenRing extends CustomPainter {
  _OpenRing(this.color, {required this.gap});

  final Color color;

  /// Radians left open, centred on the bottom-right.
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final rect = (Offset.zero & size).deflate(1);
    if (gap == 0) {
      canvas.drawOval(rect, paint);
      return;
    }
    canvas.drawArc(
        rect, math.pi / 4 + gap / 2, 2 * math.pi - gap, false, paint);
  }

  @override
  bool shouldRepaint(_OpenRing old) => old.color != color || old.gap != gap;
}
