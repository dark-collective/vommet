import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:starfield/starfield.dart';

/// Vommet: particle sprites drawn in code instead of shipped as images, for
/// effects whose particles are plain shapes (fireworks sparks, raindrops).
/// They are white so each particle's color tints them.
class DrawnParticleSprite {
  /// A soft round spark.
  static Future<ParticleSprite> spark({int size = 32}) {
    return _draw(size, size, (canvas, w, h) {
      final center = Offset(w / 2, h / 2);
      final paint = Paint()
        ..shader = ui.Gradient.radial(center, w / 2, const [
          Color(0xFFFFFFFF),
          Color(0xCCFFFFFF),
          Color(0x00FFFFFF),
        ], const [
          0,
          0.35,
          1,
        ]);
      canvas.drawCircle(center, w / 2, paint);
    });
  }

  /// A thin falling streak, brightest at its lower end.
  static Future<ParticleSprite> drop({int width = 6, int height = 40}) {
    return _draw(width, height, (canvas, w, h) {
      final paint = Paint()
        ..shader = ui.Gradient.linear(Offset(w / 2, 0), Offset(w / 2, h),
            const [Color(0x00FFFFFF), Color(0xFFFFFFFF)]);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(w / 2 - 1.5, 0, 3, h), const Radius.circular(1.5)),
          paint);
    });
  }

  static Future<ParticleSprite> _draw(int width, int height,
      void Function(Canvas canvas, double w, double h) paint) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    paint(canvas, width.toDouble(), height.toDouble());
    final image = await recorder.endRecording().toImage(width, height);
    final sprite = ParticleSprite();
    await sprite.init(image: image);
    return sprite;
  }
}
