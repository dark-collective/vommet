import 'dart:async';
import 'dart:math';

import 'package:commet/cache/file_provider.dart';
import 'package:commet/utils/voice_message.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// A received voice message: play/pause, waveform with progress (tap or drag
/// to seek), elapsed/total time and a playback-speed toggle.
class VoiceMessagePlayer extends StatefulWidget {
  const VoiceMessagePlayer({
    required this.file,
    this.duration,
    this.waveform,
    super.key,
  });

  final FileProvider file;
  final Duration? duration;

  /// 0..1024 per bar (MSC1767); a flat placeholder is drawn when missing.
  final List<int>? waveform;

  @override
  State<VoiceMessagePlayer> createState() => _VoiceMessagePlayerState();
}

class _VoiceMessagePlayerState extends State<VoiceMessagePlayer> {
  static const _speeds = [1.0, 1.5, 2.0];
  static const _bars = 48;

  final Player player = Player();
  late final List<StreamSubscription> subs;

  bool loading = false;
  bool loaded = false;
  bool playing = false;
  Duration position = Duration.zero;
  Duration? mediaDuration;
  int speedIndex = 0;

  Duration get total => mediaDuration ?? widget.duration ?? Duration.zero;

  double get progress {
    final t = total.inMilliseconds;
    if (t <= 0) return 0;
    return (position.inMilliseconds / t).clamp(0.0, 1.0);
  }

  @override
  void initState() {
    super.initState();
    subs = [
      player.stream.playing.listen((p) {
        if (mounted) setState(() => playing = p);
      }),
      player.stream.position.listen((p) {
        if (mounted) setState(() => position = p);
      }),
      player.stream.duration.listen((d) {
        if (mounted && d > Duration.zero) setState(() => mediaDuration = d);
      }),
      player.stream.completed.listen((done) {
        if (done && mounted) {
          player.pause();
          player.seek(Duration.zero);
          setState(() => position = Duration.zero);
        }
      }),
    ];
  }

  @override
  void dispose() {
    for (final s in subs) {
      s.cancel();
    }
    player.dispose();
    super.dispose();
  }

  Future<void> togglePlay() async {
    if (playing) {
      await player.pause();
      return;
    }
    if (!loaded) {
      setState(() => loading = true);
      final uri = await widget.file.resolve();
      if (!mounted) return;
      if (uri == null) {
        setState(() => loading = false);
        return;
      }
      await player.open(Media(uri.toString()), play: false);
      await player.setPlaylistMode(PlaylistMode.none);
      await player.setRate(_speeds[speedIndex]);
      loaded = true;
      if (mounted) setState(() => loading = false);
    }
    await player.play();
  }

  Future<void> cycleSpeed() async {
    setState(() => speedIndex = (speedIndex + 1) % _speeds.length);
    if (loaded) await player.setRate(_speeds[speedIndex]);
  }

  Future<void> seekTo(double fraction) async {
    if (!loaded) return;
    final target = total * fraction.clamp(0.0, 1.0);
    setState(() => position = target);
    await player.seek(target);
  }

  String get speedLabel {
    final s = _speeds[speedIndex];
    return s == s.roundToDouble() ? "${s.toInt()}×" : "$s×";
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bars = widget.waveform == null
        ? List<int>.filled(_bars, 220)
        : VoiceMessage.resample(widget.waveform!, _bars);
    final timeText = VoiceMessage.formatDuration(
        playing || position > Duration.zero ? position : total);

    return Container(
      constraints: const BoxConstraints(maxWidth: 360),
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
      decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 40,
            height: 40,
            child: loading
                ? const Padding(
                    padding: EdgeInsets.all(10),
                    child: CircularProgressIndicator(strokeWidth: 2))
                : IconButton(
                    tooltip: playing ? "Pause" : "Play voice message",
                    icon: Icon(playing ? Icons.pause : Icons.play_arrow,
                        color: scheme.primary),
                    onPressed: togglePlay,
                  ),
          ),
          Flexible(
            child: LayoutBuilder(builder: (context, c) {
              final width = min(c.maxWidth, 220.0);
              void seekFromX(double x) => seekTo(x / width);
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => seekFromX(d.localPosition.dx),
                onHorizontalDragUpdate: (d) => seekFromX(d.localPosition.dx),
                child: SizedBox(
                  width: width,
                  height: 32,
                  child: CustomPaint(
                    painter: VoiceWaveformPainter(
                      bars: bars,
                      progress: progress,
                      played: scheme.primary,
                      unplayed: scheme.onSurface.withAlpha(90),
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 40,
            child: tiamat.Text.labelLow(timeText),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: cycleSpeed,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: tiamat.Text.labelLow(speedLabel),
            ),
          ),
        ],
      ),
    );
  }
}

/// Rounded bars, played part in [played] colour.
class VoiceWaveformPainter extends CustomPainter {
  VoiceWaveformPainter({
    required this.bars,
    required this.progress,
    required this.played,
    required this.unplayed,
  });

  final List<int> bars;
  final double progress;
  final Color played;
  final Color unplayed;

  @override
  void paint(Canvas canvas, Size size) {
    if (bars.isEmpty) return;
    final slot = size.width / bars.length;
    final barWidth = max(1.5, slot * 0.6);
    final paint = Paint()..strokeCap = StrokeCap.round;
    for (var i = 0; i < bars.length; i++) {
      final level = bars[i] / VoiceMessage.waveformMax;
      final h = max(3.0, level * size.height);
      final x = i * slot + slot / 2;
      paint
        ..color = (i + 0.5) / bars.length <= progress ? played : unplayed
        ..strokeWidth = barWidth;
      canvas.drawLine(Offset(x, (size.height - h) / 2 + barWidth / 2),
          Offset(x, (size.height + h) / 2 - barWidth / 2), paint);
    }
  }

  @override
  bool shouldRepaint(VoiceWaveformPainter old) =>
      old.progress != progress ||
      old.bars != bars ||
      old.played != played ||
      old.unplayed != unplayed;
}
