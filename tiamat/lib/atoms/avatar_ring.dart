import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Vommet: a thin ring around an avatar, open at the bottom-right where a
/// small glyph sits beside the picture instead of on top of it. Marks a room
/// type (headphones on voice rooms) without covering the room's picture; the
/// ring's colour can carry state (dim when a voice room is empty, green
/// while people are in it).
class AvatarRing extends StatelessWidget {
  const AvatarRing({
    super.key,
    required this.child,
    required this.size,
    required this.color,
    this.glyph,
    this.glyphColor,
  });

  /// The avatar, at most [size] - 8 across (2 px ring + 2 px gap each side).
  final Widget child;

  /// Outer diameter of the ring.
  final double size;

  final Color color;

  final IconData? glyph;

  /// Defaults to [color].
  final Color? glyphColor;

  /// Room the avatar gets inside a ring of [size].
  static double innerSize(double size) => size - 8;

  @override
  Widget build(BuildContext context) {
    final glyphSize = (size * 0.42).roundToDouble().clamp(10.0, 14.0);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CustomPaint(
                painter: _OpenRing(color, gap: glyph == null ? 0 : 1.24)),
          ),
          Positioned(left: 4, top: 4, right: 4, bottom: 4, child: child),
          if (glyph != null)
            Positioned(
              right: -glyphSize / 3,
              bottom: -glyphSize / 3,
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
