import 'dart:math';

import 'package:commet/utils/voice_message.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Shown in place of the text field while a voice message is recording:
/// cancel (hands-free mode), a red dot with the elapsed time, a live level
/// meter, and a "slide to cancel" hint in press-and-hold mode.
class VoiceRecordingBar extends StatelessWidget {
  const VoiceRecordingBar({
    required this.elapsed,
    required this.levels,
    required this.holdMode,
    required this.onCancel,
    this.dragDx = 0,
    this.cancelDistance = 80,
    super.key,
  });

  final Duration elapsed;

  /// Recent input levels, 0..1, oldest first.
  final List<double> levels;
  final bool holdMode;
  final VoidCallback onCancel;

  /// How far the finger has slid left (negative) in hold mode.
  final double dragDx;
  final double cancelDistance;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cancelFraction = (-dragDx / cancelDistance).clamp(0.0, 1.0);
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          if (!holdMode)
            IconButton(
              tooltip: "Cancel recording",
              icon: Icon(Icons.delete_outline, color: scheme.error),
              onPressed: onCancel,
            )
          else
            const SizedBox(width: 12),
          Container(
            width: 10,
            height: 10,
            decoration:
                BoxDecoration(color: scheme.error, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          tiamat.Text.label(VoiceMessage.formatDuration(elapsed)),
          const SizedBox(width: 12),
          Expanded(
            child: CustomPaint(
              painter: _LevelMeterPainter(
                  levels: levels, color: scheme.primary.withAlpha(200)),
              child: const SizedBox.expand(),
            ),
          ),
          if (holdMode)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Opacity(
                opacity: 1 - cancelFraction * 0.7,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.chevron_left,
                        size: 18,
                        color: Color.lerp(
                            scheme.onSurface, scheme.error, cancelFraction)),
                    tiamat.Text.labelLow("Slide to cancel"),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LevelMeterPainter extends CustomPainter {
  _LevelMeterPainter({required this.levels, required this.color});
  final List<double> levels;
  final Color color;

  static const _slot = 5.0;

  @override
  void paint(Canvas canvas, Size size) {
    final count = (size.width / _slot).floor();
    if (count <= 0) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    // newest level at the right edge
    final shown =
        levels.length > count ? levels.sublist(levels.length - count) : levels;
    final offset = count - shown.length;
    for (var i = 0; i < shown.length; i++) {
      final h = max(3.0, shown[i].clamp(0.0, 1.0) * (size.height - 8));
      final x = (offset + i) * _slot + _slot / 2;
      canvas.drawLine(Offset(x, (size.height - h) / 2),
          Offset(x, (size.height + h) / 2), paint);
    }
  }

  @override
  // The caller passes a fresh list on every update.
  bool shouldRepaint(_LevelMeterPainter old) =>
      !identical(old.levels, levels) || old.color != color;
}
