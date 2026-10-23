import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Vommet issue 641: swiping a message from right to left starts a reply to
/// it, like other chat apps.
///
/// On mobile the room sits in `OverlappingPanels`, which takes every
/// sideways drag to slide the side panels. So the reply swipe only starts
/// when the finger goes down near the right edge of the message (just inside
/// the system back-gesture strip, if there is one); a swipe that starts
/// further in still moves the panels as before.
class SwipeToReply extends StatefulWidget {
  const SwipeToReply({
    required this.child,
    required this.replyAction,
    super.key,
  });

  final Widget child;

  /// Called when a swipe could start: returns what to run when the swipe
  /// goes far enough, or null if this message can't be replied to (then the
  /// drag is left to the side panels).
  final VoidCallback? Function() replyAction;

  /// How far in from the right edge (past the system gesture strip) a reply
  /// swipe may start.
  static const double edgeWidth = 48;

  /// How far the message has to be pulled left to start the reply.
  static const double triggerDistance = 64;

  /// How far the message can be pulled left at most.
  static const double maxDistance = 96;

  /// Whether a touch at [localX] (from the message's left side) on a message
  /// [width] wide starts close enough to the right edge for a reply swipe.
  @visibleForTesting
  static bool startsAtEdge(double localX, double width, double gestureInset) {
    return localX >= width - gestureInset - edgeWidth;
  }

  /// Where the message sits for a drag of [dragged] pixels (negative =
  /// leftwards): it follows the finger to the trigger distance, then slows
  /// down, and never moves right.
  @visibleForTesting
  static double offsetFor(double dragged) {
    if (dragged >= 0) return 0;
    final pulled = -dragged;
    if (pulled <= triggerDistance) return dragged;
    final extra = (pulled - triggerDistance) / 3;
    return -math.min(maxDistance, triggerDistance + extra);
  }

  @override
  State<SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<SwipeToReply>
    with SingleTickerProviderStateMixin {
  late final AnimationController _back;
  double _dragged = 0;
  double _offset = 0;
  double _settleFrom = 0;
  VoidCallback? _action;

  @override
  void initState() {
    super.initState();
    _back = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200))
      ..addListener(() {
        setState(() => _offset = _settleFrom * (1 - _back.value));
      });
  }

  @override
  void dispose() {
    _back.dispose();
    super.dispose();
  }

  bool _allowPointer(PointerDownEvent event) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return false;
    final local = box.globalToLocal(event.position);
    final inset = MediaQuery.systemGestureInsetsOf(context).right;
    if (!SwipeToReply.startsAtEdge(local.dx, box.size.width, inset)) {
      return false;
    }
    _action = widget.replyAction();
    return _action != null;
  }

  void _onStart(DragStartDetails details) {
    _back.stop();
    _dragged = _offset;
  }

  void _onUpdate(DragUpdateDetails details) {
    final wasPast = _offset <= -SwipeToReply.triggerDistance;
    _dragged += details.delta.dx;
    setState(() => _offset = SwipeToReply.offsetFor(_dragged));
    final isPast = _offset <= -SwipeToReply.triggerDistance;
    if (isPast && !wasPast) HapticFeedback.lightImpact();
  }

  void _onEnd(DragEndDetails details) {
    if (_offset <= -SwipeToReply.triggerDistance) _action?.call();
    _settle();
  }

  void _settle() {
    _action = null;
    _dragged = 0;
    if (_offset == 0) return;
    _settleFrom = _offset;
    _back.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final progress =
        (-_offset / SwipeToReply.triggerDistance).clamp(0.0, 1.0).toDouble();

    return RawGestureDetector(
      gestures: {
        _EdgeDragRecognizer:
            GestureRecognizerFactoryWithHandlers<_EdgeDragRecognizer>(
          () => _EdgeDragRecognizer(allow: _allowPointer),
          (recognizer) => recognizer
            ..allow = _allowPointer
            ..onStart = _onStart
            ..onUpdate = _onUpdate
            ..onEnd = _onEnd
            ..onCancel = _settle,
        ),
      },
      child: Stack(
        children: [
          if (_offset != 0)
            Positioned.fill(
              child: Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Opacity(
                    opacity: progress,
                    child: Transform.scale(
                      scale: 0.6 + 0.4 * progress,
                      child: Icon(Icons.reply,
                          color: Theme.of(context).colorScheme.primary),
                    ),
                  ),
                ),
              ),
            ),
          Transform.translate(
            offset: Offset(_offset, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

/// A sideways drag that only joins the gesture arena for touches [allow]
/// accepts, so other touches go to the side panels' drag.
class _EdgeDragRecognizer extends HorizontalDragGestureRecognizer {
  _EdgeDragRecognizer({required this.allow})
      : super(supportedDevices: {PointerDeviceKind.touch});

  bool Function(PointerDownEvent event) allow;

  @override
  bool isPointerAllowed(PointerDownEvent event) =>
      super.isPointerAllowed(event) && allow(event);
}
