import 'dart:math' as math;

import 'package:commet/utils/links/link_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

class LinkSpan {
  static InlineSpan create(String text,
      {required BuildContext context,
      required String clientId,
      destination,
      TextStyle? style}) {
    var color = Theme.of(context).extension<ExtraColors>()?.linkColor ??
        Theme.of(context).colorScheme.primary;

    final target = destination?.toString() ?? "";

    return TextSpan(
        text: text,
        style: (style ?? const TextStyle())
            .copyWith(color: color, decorationColor: color),
        recognizer: LinkGestureRecognizer()
          ..highlightContext = context
          ..highlightColor = color
          ..onTap = () {
            if (destination != null) {
              LinkUtils.open(destination, clientId: clientId, context: context);
            }
          }
          ..onLongPress = target.isEmpty
              ? null
              : () {
                  // Vommet issue 690: a touch long-press on the link copies
                  // its target, with the usual long-press feedback.
                  Clipboard.setData(ClipboardData(text: target));
                  if (context.mounted) Feedback.forLongPress(context);
                });
  }
}

/// Vommet: a link's tap plus a touch-only long-press (Vommet issue 690). A
/// [TextSpan] takes one recognizer, so this tap recognizer also enters a
/// [LongPressGestureRecognizer] into the arena for each touch. The span is
/// hit first, so its long-press timer fires before the message's own
/// long-press and wins; a long-press anywhere else on the message, mouse
/// input and taps behave as before. Staying a [TapGestureRecognizer] keeps
/// the link's semantics tap and pointer cursor.
class LinkGestureRecognizer extends TapGestureRecognizer {
  LinkGestureRecognizer();

  static const _pressKinds = {
    PointerDeviceKind.touch,
    PointerDeviceKind.stylus
  };

  late final LongPressGestureRecognizer _longPress =
      LongPressGestureRecognizer(supportedDevices: _pressKinds)
        ..onLongPress = () {
          _phase?.value = _PressPhase.fired;
          _endHighlight();
          onLongPress?.call();
        }
        ..onLongPressCancel = _releaseHighlight;

  VoidCallback? onLongPress;

  /// Vommet issue 713: while a touch long-press is held, a highlight spreads
  /// over the link from the finger and fills it as the press nears
  /// triggering. It's drawn in the root overlay above [highlightContext], in
  /// [highlightColor]; without a context there's no highlight.
  BuildContext? highlightContext;
  Color? highlightColor;

  ValueNotifier<_PressPhase>? _phase;
  int? _highlightPointer;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    if (onLongPress == null) return;
    _longPress.addPointer(event);
    if (_pressKinds.contains(event.kind)) _showHighlight(event);
  }

  void _showHighlight(PointerDownEvent event) {
    final context = highlightContext;
    if (_phase != null || context == null || !context.mounted) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    final overlayBox = overlay?.context.findRenderObject();
    if (overlay == null || overlayBox is! RenderBox) return;

    final rects = _linkRects(event, overlayBox);
    if (rects.isEmpty) return;

    final phase = ValueNotifier(_PressPhase.pressing);
    late final OverlayEntry entry;
    entry = OverlayEntry(
        builder: (_) => _LinkPressHighlight(
            rects: rects,
            origin: overlayBox.globalToLocal(event.position),
            color: (highlightColor ?? Theme.of(context).colorScheme.primary)
                .withAlpha(72),
            duration: _longPress.deadline ?? kLongPressTimeout,
            animate: !(MediaQuery.maybeDisableAnimationsOf(context) ?? false),
            phase: phase,
            onDone: () {
              entry.remove();
              entry.dispose();
            }));
    overlay.insert(entry);

    _phase = phase;
    _highlightPointer = event.pointer;
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
  }

  /// The link's line boxes in [overlayBox]'s coordinates, from the paragraph
  /// under the pointer; empty when the link isn't in a plain paragraph.
  List<RRect> _linkRects(PointerDownEvent event, RenderBox overlayBox) {
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(result, event.position, event.viewId);
    for (final entry in result.path) {
      final paragraph = entry.target;
      if (paragraph is! RenderParagraph || !paragraph.attached) continue;
      final range = _rangeIn(paragraph.text);
      if (range == null) continue;
      final transform = paragraph.getTransformTo(overlayBox);
      return [
        for (final box in paragraph.getBoxesForSelection(
            TextSelection(baseOffset: range.start, extentOffset: range.end)))
          RRect.fromRectAndRadius(
              MatrixUtils.transformRect(transform, box.toRect()).inflate(2),
              const Radius.circular(4)),
      ];
    }
    return const [];
  }

  /// Where this recognizer's span sits in [text], in UTF-16 code units
  /// (placeholders count as one).
  TextRange? _rangeIn(InlineSpan text) {
    var offset = 0;
    TextRange? range;
    text.visitChildren((span) {
      if (span is TextSpan) {
        final length = span.text?.length ?? 0;
        if (identical(span.recognizer, this)) {
          range = TextRange(start: offset, end: offset + length);
          return false;
        }
        offset += length;
      } else if (span is PlaceholderSpan) {
        offset += 1;
      }
      return true;
    });
    return range;
  }

  void _onPointer(PointerEvent event) {
    if (event.pointer != _highlightPointer) return;
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      _releaseHighlight();
    }
  }

  void _releaseHighlight() {
    if (_phase?.value == _PressPhase.pressing) {
      _phase?.value = _PressPhase.released;
    }
    _endHighlight();
  }

  void _endHighlight() {
    if (_phase == null) return;
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    _phase = null;
    _highlightPointer = null;
  }

  @override
  void dispose() {
    _releaseHighlight();
    _longPress.dispose();
    super.dispose();
  }
}

enum _PressPhase { pressing, fired, released }

/// The press highlight: a circle growing from [origin] over [duration],
/// clipped to the link's [rects]. It completes and fades out when the press
/// fires, and fades out when it's let go early. With animations turned off
/// in the system it shows the whole link at once.
class _LinkPressHighlight extends StatefulWidget {
  const _LinkPressHighlight(
      {required this.rects,
      required this.origin,
      required this.color,
      required this.duration,
      required this.animate,
      required this.phase,
      required this.onDone});

  final List<RRect> rects;
  final Offset origin;
  final Color color;
  final Duration duration;
  final bool animate;
  final ValueListenable<_PressPhase> phase;
  final VoidCallback onDone;

  @override
  State<_LinkPressHighlight> createState() => _LinkPressHighlightState();
}

class _LinkPressHighlightState extends State<_LinkPressHighlight>
    with TickerProviderStateMixin {
  late final AnimationController _spread =
      AnimationController(vsync: this, duration: widget.duration);
  late final AnimationController _opacity = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 150), value: 1);

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      _spread.forward();
    } else {
      _spread.value = 1;
    }
    widget.phase.addListener(_onPhase);
  }

  Future<void> _onPhase() async {
    final phase = widget.phase.value;
    if (phase == _PressPhase.pressing) return;
    widget.phase.removeListener(_onPhase);
    if (widget.animate) {
      if (phase == _PressPhase.fired) {
        await _spread.animateTo(1, duration: const Duration(milliseconds: 80));
      }
      if (!mounted) return;
      await _opacity.reverse();
    }
    if (mounted) widget.onDone();
  }

  @override
  void dispose() {
    widget.phase.removeListener(_onPhase);
    _spread.dispose();
    _opacity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: FadeTransition(
          opacity: _opacity,
          child: CustomPaint(
              key: const ValueKey("link-press-highlight"),
              painter: _LinkPressPainter(
                  rects: widget.rects,
                  origin: widget.origin,
                  color: widget.color,
                  progress: _spread)),
        ),
      ),
    );
  }
}

class _LinkPressPainter extends CustomPainter {
  _LinkPressPainter(
      {required this.rects,
      required this.origin,
      required this.color,
      required this.progress})
      : super(repaint: progress);

  final List<RRect> rects;
  final Offset origin;
  final Color color;
  final Animation<double> progress;

  @override
  void paint(Canvas canvas, Size size) {
    final clip = Path();
    var bounds = rects.first.outerRect;
    for (final rect in rects) {
      clip.addRRect(rect);
      bounds = bounds.expandToInclude(rect.outerRect);
    }
    // Far enough from the finger to cover every corner of the link.
    final reach = [
      bounds.topLeft,
      bounds.topRight,
      bounds.bottomLeft,
      bounds.bottomRight
    ].map((corner) => (corner - origin).distance).reduce(math.max);

    canvas.save();
    canvas.clipPath(clip);
    canvas.drawCircle(origin, reach * progress.value, Paint()..color = color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LinkPressPainter oldDelegate) =>
      oldDelegate.rects != rects ||
      oldDelegate.origin != origin ||
      oldDelegate.color != color;
}
