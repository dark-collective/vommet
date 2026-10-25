import 'dart:math';

import 'package:commet/cache/file_provider.dart';
import 'package:commet/ui/molecules/voice_message/voice_message_player.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/utils/voice_transcription.dart';
import 'package:flutter/material.dart';

/// A voice bubble with speech-to-text the way Telegram does it (#70): a "→A"
/// button at the end of the waveform row; tapping it grows the bubble and
/// the text appears under the waveform (a shimmer while it's worked out, a
/// ring running round the button), and the button turns into a chevron that
/// folds the text away again.
class TranscribableVoiceMessage extends StatefulWidget {
  const TranscribableVoiceMessage({
    required this.file,
    this.mimeType,
    this.duration,
    this.waveform,
    this.transcription,
    this.playerBuilder = VoiceMessagePlayer.new,
    super.key,
  });

  final FileProvider file;
  final String? mimeType;
  final Duration? duration;
  final List<int>? waveform;

  /// Defaults to [VoiceTranscription.instance].
  final VoiceTranscription? transcription;

  /// The bubble; tests swap out the real player (it needs libmpv).
  final Widget Function({
    required FileProvider file,
    Duration? duration,
    List<int>? waveform,
    Widget? trailing,
    Widget? footer,
    Key? key,
  }) playerBuilder;

  @override
  State<TranscribableVoiceMessage> createState() =>
      _TranscribableVoiceMessageState();
}

class _TranscribableVoiceMessageState extends State<TranscribableVoiceMessage> {
  late VoiceTranscription transcription;
  late ValueNotifier<TranscriptState> state;
  bool collapsed = false;

  String get key => widget.file.fileIdentifier;

  @override
  void initState() {
    super.initState();
    transcription = widget.transcription ?? VoiceTranscription.instance;
    state = transcription.stateFor(key);
  }

  @override
  void didUpdateWidget(TranscribableVoiceMessage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.fileIdentifier != key) {
      state = transcription.stateFor(key);
    }
  }

  Future<void> start() async {
    final model = transcription.model;
    if (!await transcription.isDownloaded(model) &&
        transcription.downloadProgress.value == null) {
      if (!mounted) return;
      final ok = await AdaptiveDialog.confirmation(
        context,
        title: "Download speech model?",
        prompt:
            "Transcription runs on this device, so the audio never leaves it. "
            "It needs a speech model (${model.label}, ${model.sizeLabel}), "
            "downloaded once from Hugging Face. You can choose a different "
            "model in Settings, under General.",
        confirmationText: "Download",
        cancelText: "Cancel",
      );
      if (ok != true) return;
    }
    setState(() => collapsed = false);
    await transcription.transcribe(widget.file, mimeType: widget.mimeType);
  }

  void onButton(TranscriptState value) {
    switch (value) {
      case TranscriptIdle() || TranscriptFailed():
        start();
      case TranscriptDownloading() || TranscriptRunning():
        transcription.cancel(key);
      case TranscriptDone():
        setState(() => collapsed = !collapsed);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TranscriptState>(
      valueListenable: state,
      builder: (context, value, _) => widget.playerBuilder(
        file: widget.file,
        duration: widget.duration,
        waveform: widget.waveform,
        trailing: TranscribeButton(
          state: value,
          collapsed: collapsed,
          onPressed: () => onButton(value),
        ),
        footer: footer(value),
      ),
    );
  }

  Widget footer(TranscriptState value) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final Widget? child = switch (value) {
      TranscriptIdle() => null,
      TranscriptDownloading(:final progress) => Text(
          "Downloading speech model…"
          "${progress == null || progress <= 0 ? "" : " ${(progress * 100).round()}%"}",
          style: muted),
      TranscriptRunning() => const TranscriptShimmer(),
      TranscriptDone() when collapsed => null,
      TranscriptDone(:final transcript) when transcript.text.isEmpty =>
        Text("No speech detected", style: muted),
      TranscriptDone(:final transcript) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SelectableText(transcript.text, style: theme.textTheme.bodyMedium),
            if (transcript.isLowConfidence)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text("Low confidence: the text may be inaccurate.",
                    style: muted),
              ),
          ],
        ),
      TranscriptFailed(:final message) => Text(message,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.error)),
    };
    if (child == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 8, 6),
      child: child,
    );
  }
}

/// Telegram's speech-to-text button: "→A" in a tinted rounded square, a ring
/// running round its edge while busy, a chevron once the text is shown.
class TranscribeButton extends StatefulWidget {
  const TranscribeButton({
    required this.state,
    required this.collapsed,
    required this.onPressed,
    super.key,
  });

  final TranscriptState state;
  final bool collapsed;
  final VoidCallback onPressed;

  @override
  State<TranscribeButton> createState() => _TranscribeButtonState();
}

class _TranscribeButtonState extends State<TranscribeButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController spin = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1200));

  bool get busy =>
      widget.state is TranscriptRunning ||
      widget.state is TranscriptDownloading;

  @override
  void initState() {
    super.initState();
    if (busy) spin.repeat();
  }

  @override
  void didUpdateWidget(TranscribeButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (busy && !spin.isAnimating) spin.repeat();
    if (!busy && spin.isAnimating) spin.stop();
  }

  @override
  void dispose() {
    spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final state = widget.state;
    final expanded = state is TranscriptDone && !widget.collapsed;
    final tooltip = switch (state) {
      TranscriptDownloading() || TranscriptRunning() => "Cancel transcription",
      TranscriptDone() =>
        widget.collapsed ? "Show transcript" : "Hide transcript",
      _ => "Transcribe",
    };
    // Determinate while downloading the model, spinning while transcribing:
    // whisper only reports progress per 30 s window, so a short message
    // would sit at 0% and then jump.
    final double? progress = switch (state) {
      TranscriptDownloading(:final progress) =>
        progress == null || progress <= 0 ? null : progress,
      _ => null,
    };

    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          mouseCursor: WidgetStateMouseCursor.clickable,
          borderRadius: BorderRadius.circular(8),
          onTap: widget.onPressed,
          child: SizedBox(
            width: 30,
            height: 30,
            child: AnimatedBuilder(
              animation: spin,
              builder: (context, child) => CustomPaint(
                foregroundPainter: busy
                    ? RoundedRectProgressPainter(
                        color: scheme.primary,
                        progress: progress,
                        phase: spin.value)
                    : null,
                child: child,
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                    color: scheme.primary.withAlpha(36),
                    borderRadius: BorderRadius.circular(8)),
                child: Center(
                  child: expanded
                      ? Icon(Icons.keyboard_arrow_up,
                          size: 20, color: scheme.primary)
                      : Row(
                          // Telegram's "→A"; the arrow is an icon because
                          // not every font has U+2192.
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.arrow_forward_rounded,
                                size: 11, color: scheme.primary),
                            Text("A",
                                style: TextStyle(
                                    fontSize: 13,
                                    height: 1,
                                    fontWeight: FontWeight.w700,
                                    color: scheme.primary)),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A stroke running along a rounded square's edge: a filled share of it for
/// [progress], or a quarter-length segment travelling round at [phase] 0..1.
class RoundedRectProgressPainter extends CustomPainter {
  RoundedRectProgressPainter(
      {required this.color, required this.progress, required this.phase});

  final Color color;
  final double? progress;
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 2.0;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(7)));
    final metric = path.computeMetrics().first;
    final length = metric.length;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    final p = progress;
    if (p != null) {
      canvas.drawPath(metric.extractPath(0, length * p.clamp(0.0, 1.0)), paint);
      return;
    }
    final start = phase * length;
    final end = start + length / 4;
    canvas.drawPath(metric.extractPath(start, min(end, length)), paint);
    if (end > length) {
      canvas.drawPath(metric.extractPath(0, end - length), paint);
    }
  }

  @override
  bool shouldRepaint(RoundedRectProgressPainter old) =>
      old.progress != progress || old.phase != phase || old.color != color;
}

/// Placeholder lines that pulse while the text is worked out.
class TranscriptShimmer extends StatefulWidget {
  const TranscriptShimmer({super.key});

  @override
  State<TranscriptShimmer> createState() => _TranscriptShimmerState();
}

class _TranscriptShimmerState extends State<TranscriptShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);

  @override
  void dispose() {
    pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface;
    Widget line(double width) => Container(
          width: width,
          height: 10,
          margin: const EdgeInsets.symmetric(vertical: 3),
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(5)),
        );
    return Semantics(
      label: "Transcribing",
      child: FadeTransition(
        opacity: Tween(begin: 0.06, end: 0.16).animate(pulse),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [line(220), line(140)],
        ),
      ),
    );
  }
}
