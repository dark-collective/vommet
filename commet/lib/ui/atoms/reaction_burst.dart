import 'dart:math';

import 'package:commet/config/preferences/bool_preference.dart';
import 'package:commet/main.dart';
import 'package:flutter/material.dart';

/// Vommet experiment: a reaction's emoji bursts out of its chip when you
/// react or a reaction arrives live. Only on this device: nothing is sent.
/// Kept here instead of preferences.dart so this topic doesn't touch that
/// busy file. Off by default: it's opt-in (operator 10-28).
final experimentReactionBursts =
    BoolPreference("vommet_experiment_reaction_bursts", defaultValue: false);

/// Which reactions arrived just now, so a chip only bursts for a live
/// reaction and never for history being loaded or scrolled into view.
class ReactionBurstSignal {
  static const Duration window = Duration(seconds: 3);

  /// A reaction older than this when it arrives (catch-up after being
  /// offline) doesn't count as live.
  static const Duration maxAge = Duration(seconds: 30);

  static final Map<String, DateTime> _recent = {};

  /// A reaction with [key] (its emoji, or mxc:// URL) arrived, sent at
  /// [sentAt].
  static void noteLive(String key, {DateTime? sentAt, DateTime? now}) {
    now ??= DateTime.now();
    if (sentAt != null && now.difference(sentAt) > maxAge) return;
    _recent.removeWhere((_, at) => now!.difference(at) > window);
    _recent[key] = now;
  }

  static bool isRecent(String key, {DateTime? now}) {
    final at = _recent[key];
    if (at == null) return false;
    return (now ?? DateTime.now()).difference(at) <= window;
  }

  /// Forget all live reactions (tests).
  static void clear() => _recent.clear();
}

/// Wraps a reaction chip's emoji: when [count] goes up (or the chip appears)
/// right after a live reaction with [emojiKey], copies of [child] fly out of
/// it and fade, in under a second.
class ReactionBurst extends StatefulWidget {
  const ReactionBurst(
      {required this.emojiKey,
      required this.count,
      required this.child,
      super.key});

  final String emojiKey;
  final int count;
  final Widget child;

  static const Duration duration = Duration(milliseconds: 850);
  static const int copies = 7;

  /// At most this many bursts start at once across the app, so a flood of
  /// reactions can't fill the screen.
  static const int maxRunning = 4;
  static int _running = 0;

  @override
  State<ReactionBurst> createState() => _ReactionBurstState();
}

class _ReactionBurstState extends State<ReactionBurst>
    with TickerProviderStateMixin {
  final List<(AnimationController, OverlayEntry)> _bursts = [];

  @override
  void initState() {
    super.initState();
    if (ReactionBurstSignal.isRecent(widget.emojiKey)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _burst());
    }
  }

  @override
  void didUpdateWidget(covariant ReactionBurst oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.emojiKey == widget.emojiKey &&
        widget.count > oldWidget.count &&
        ReactionBurstSignal.isRecent(widget.emojiKey)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _burst());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Covered by another screen (e.g. a fullscreen stream): the burst's
    // ticker is muted and would never finish, so drop it.
    if (!TickerMode.of(context)) {
      for (final burst in List.of(_bursts)) {
        _end(burst);
      }
    }
  }

  bool get _enabled =>
      preferences.messageEffectsEnabled.value &&
      experimentReactionBursts.value &&
      !MediaQuery.disableAnimationsOf(context) &&
      // Not while the chat is hidden behind another screen, such as a
      // fullscreen stream.
      TickerMode.of(context) &&
      (ModalRoute.of(context)?.isCurrent ?? true);

  void _burst() {
    if (!mounted || !_enabled) return;
    if (ReactionBurst._running >= ReactionBurst.maxRunning) return;

    final overlay = Overlay.maybeOf(context);
    final box = context.findRenderObject() as RenderBox?;
    if (overlay == null || box == null || !box.hasSize) return;
    final overlayBox = overlay.context.findRenderObject() as RenderBox?;
    if (overlayBox == null) return;

    final origin =
        box.localToGlobal(box.size.center(Offset.zero), ancestor: overlayBox);
    final size = box.size;
    final rng = Random();
    // Mostly up and to the sides, like the chip is popping.
    final angles = List.generate(ReactionBurst.copies, (i) {
      final spread = (i / (ReactionBurst.copies - 1)) - 0.5;
      return -pi / 2 + spread * pi * 1.1 + (rng.nextDouble() - 0.5) * 0.3;
    });
    final distances =
        List.generate(ReactionBurst.copies, (_) => 26 + rng.nextDouble() * 22);

    final controller =
        AnimationController(vsync: this, duration: ReactionBurst.duration);
    final curve = CurvedAnimation(parent: controller, curve: Curves.easeOut);

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => IgnorePointer(
        child: AnimatedBuilder(
          animation: curve,
          builder: (context, _) {
            final t = curve.value;
            return Stack(
              children: [
                for (int i = 0; i < ReactionBurst.copies; i++)
                  Positioned(
                    left: origin.dx -
                        size.width / 2 +
                        cos(angles[i]) * distances[i] * t,
                    top: origin.dy -
                        size.height / 2 +
                        sin(angles[i]) * distances[i] * t +
                        // a little gravity at the end
                        12 * t * t,
                    child: Opacity(
                      opacity: (1 - controller.value).clamp(0.0, 1.0),
                      child: Transform.scale(
                        scale: 0.7 + 0.4 * (1 - t),
                        child: KeyedSubtree(
                            key: const ValueKey("reaction-burst-copy"),
                            child: widget.child),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );

    ReactionBurst._running++;
    final burst = (controller, entry);
    _bursts.add(burst);
    overlay.insert(entry);
    controller.forward().whenComplete(() => _end(burst));
  }

  void _end((AnimationController, OverlayEntry) burst) {
    if (!_bursts.remove(burst)) return;
    ReactionBurst._running--;
    burst.$2.remove();
    burst.$1.dispose();
  }

  @override
  void dispose() {
    for (final burst in List.of(_bursts)) {
      _end(burst);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
