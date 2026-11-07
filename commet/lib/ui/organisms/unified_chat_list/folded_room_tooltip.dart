// Vommet: the room name beside an avatar in the folded list (Vommet issue 1154).
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class FoldedRoomTooltip extends StatefulWidget {
  const FoldedRoomTooltip({
    super.key,
    required this.name,
    required this.child,
  });

  static const avatarSize = 44.0;

  final String name;
  final Widget child;

  @override
  State<FoldedRoomTooltip> createState() => _FoldedRoomTooltipState();
}

class _FoldedRoomTooltipState extends State<FoldedRoomTooltip> {
  final _overlay = OverlayPortalController();
  Timer? _timer;
  bool _keyboardFocus = false;

  void _hide() {
    _timer?.cancel();
    if (_overlay.isShowing) _overlay.hide();
  }

  void _hover(PointerEnterEvent event) {
    if (event.kind == PointerDeviceKind.touch || _overlay.isShowing) return;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 400), _overlay.show);
  }

  void _focusChanged(bool focused) {
    final keyboardFocus = focused &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    if (_keyboardFocus == keyboardFocus) return;
    setState(() => _keyboardFocus = keyboardFocus);
    _timer?.cancel();
    if (keyboardFocus) {
      _overlay.show();
    } else {
      _hide();
    }
  }

  void _longPress() {
    _timer?.cancel();
    _overlay.show();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visible = TooltipVisibility.of(context) &&
        (ModalRoute.isCurrentOf(context) ?? true);
    final scheme = Theme.of(context).colorScheme;
    return OverlayPortal.overlayChildLayoutBuilder(
      controller: _overlay,
      overlayChildBuilder: (context, layout) =>
          visible ? _buildBubble(context, layout) : const SizedBox.shrink(),
      child: Focus(
        canRequestFocus: false,
        onFocusChange: _focusChanged,
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape &&
              visible &&
              _overlay.isShowing) {
            _hide();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: MouseRegion(
          onEnter: visible ? _hover : null,
          onExit: (_) {
            if (!_keyboardFocus) _hide();
          },
          child: Listener(
            onPointerDown: (_) => _hide(),
            child: GestureDetector(
              supportedDevices: const {
                PointerDeviceKind.touch,
                PointerDeviceKind.stylus,
                PointerDeviceKind.invertedStylus,
              },
              onLongPress: visible ? _longPress : null,
              onLongPressEnd: visible
                  ? (_) {
                      _timer = Timer(const Duration(milliseconds: 1500), _hide);
                    }
                  : null,
              child: Stack(
                children: [
                  widget.child,
                  if (_keyboardFocus)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Center(
                          child: SizedBox.square(
                            dimension: FoldedRoomTooltip.avatarSize + 6,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border:
                                    Border.all(color: scheme.primary, width: 2),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBubble(BuildContext context, OverlayChildLayoutInfo layout) {
    const margin = 8.0;
    const gap = 6.0;
    const tail = _BubbleBorder.tail;
    const padding = EdgeInsets.symmetric(horizontal: 10, vertical: 8);
    final viewport = (Offset.zero & layout.overlaySize).deflate(margin);
    // The whole row owns hover, including badges. Placement follows its picture.
    final target = MatrixUtils.transformRect(
      layout.childPaintTransform,
      Rect.fromCenter(
        center: layout.childSize.center(Offset.zero),
        width: FoldedRoomTooltip.avatarSize,
        height: FoldedRoomTooltip.avatarSize,
      ),
    );
    if (viewport.isEmpty || !target.overlaps(viewport)) {
      return const SizedBox.shrink();
    }

    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.bodySmall!.copyWith(
          inherit: false,
          color: scheme.onSurface,
          fontSize: 13,
          height: 1.3,
        );
    final text = TextSpan(text: widget.name, style: style);
    final direction = Directionality.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final locale = Localizations.maybeLocaleOf(context);
    final painter = TextPainter(
      text: text,
      textDirection: direction,
      textScaler: scaler,
      locale: locale,
      maxLines: 3,
      ellipsis: '…',
    );

    final maxWidth = math.min(280.0, viewport.width);
    void measure(double width) {
      painter.layout(maxWidth: math.max(0, width - padding.horizontal));
    }

    measure(maxWidth);
    double width = painter.width.ceilToDouble() + padding.horizontal;
    final right = viewport.right - target.right - gap - tail;
    final left = target.left - viewport.left - gap - tail;
    final above = target.top - viewport.top - gap - tail;
    final below = viewport.bottom - target.bottom - gap - tail;
    final AxisDirection side;
    if (width <= right) {
      side = AxisDirection.right;
    } else if (width <= left) {
      side = AxisDirection.left;
    } else if (math.max(right, left) >= 120) {
      side = right >= left ? AxisDirection.right : AxisDirection.left;
      width = math.max(right, left);
      measure(width);
    } else {
      final preferredHeight = painter.height + padding.vertical;
      side = preferredHeight <= above || above > below
          ? AxisDirection.up
          : AxisDirection.down;
    }
    final horizontal =
        side == AxisDirection.right || side == AxisDirection.left;
    final maxHeight = switch (side) {
      AxisDirection.up => above,
      AxisDirection.down => below,
      _ => viewport.height,
    };
    final height =
        math.min(painter.height.ceilToDouble() + padding.vertical, maxHeight);
    painter.dispose();
    if (width <= padding.horizontal || height <= padding.vertical) {
      return const SizedBox.shrink();
    }

    final size =
        Size(width + (horizontal ? tail : 0), height + (horizontal ? 0 : tail));
    final x = switch (side) {
      AxisDirection.right => target.right + gap,
      AxisDirection.left => target.left - gap - size.width,
      _ => (target.center.dx - size.width / 2).clamp(
          viewport.left, math.max(viewport.left, viewport.right - size.width)),
    };
    final y = switch (side) {
      AxisDirection.up => target.top - gap - size.height,
      AxisDirection.down => target.bottom + gap,
      _ => (target.center.dy - size.height / 2).clamp(
          viewport.top, math.max(viewport.top, viewport.bottom - size.height)),
    };
    final tailPadding = switch (side) {
      AxisDirection.right => const EdgeInsets.only(left: tail),
      AxisDirection.left => const EdgeInsets.only(right: tail),
      AxisDirection.up => const EdgeInsets.only(bottom: tail),
      AxisDirection.down => const EdgeInsets.only(top: tail),
    };
    final fill = scheme.surfaceContainerHigh;
    return Positioned(
      left: x.toDouble(),
      top: y.toDouble(),
      width: size.width,
      height: size.height,
      child: IgnorePointer(
        child: ExcludeSemantics(
          child: CustomPaint(
            painter: _BubbleBorder(
              side: side,
              tip: horizontal ? target.center.dy - y : target.center.dx - x,
              fill: fill,
              outline: Color.alphaBlend(
                  scheme.onSurface.withValues(alpha: .26), fill),
            ),
            child: Padding(
              padding: padding + tailPadding,
              child: Text.rich(
                text,
                textDirection: direction,
                textScaler: scaler,
                locale: locale,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BubbleBorder extends CustomPainter {
  const _BubbleBorder({
    required this.side,
    required this.tip,
    required this.fill,
    required this.outline,
  });

  static const tail = 7.0;
  final AxisDirection side;
  final double tip;
  final Color fill;
  final Color outline;

  @override
  void paint(Canvas canvas, Size size) {
    final body = Rect.fromLTRB(
      side == AxisDirection.right ? tail : 0,
      side == AxisDirection.down ? tail : 0,
      size.width - (side == AxisDirection.left ? tail : 0),
      size.height - (side == AxisDirection.up ? tail : 0),
    ).deflate(.5);
    final radius = math.min(10.0, body.shortestSide / 2);
    final rounded = Path()
      ..addRRect(RRect.fromRectAndRadius(body, Radius.circular(radius)));
    final horizontal =
        side == AxisDirection.right || side == AxisDirection.left;
    final length = horizontal ? body.height : body.width;
    final inset = math.min(radius + 5, length / 2);
    final middle = tip.clamp(inset, length - inset);
    final (a, b, c) = switch (side) {
      AxisDirection.right => (
          Offset(body.left + 1, middle - 5),
          Offset(.5, middle),
          Offset(body.left + 1, middle + 5)
        ),
      AxisDirection.left => (
          Offset(body.right - 1, middle - 5),
          Offset(size.width - .5, middle),
          Offset(body.right - 1, middle + 5)
        ),
      AxisDirection.up => (
          Offset(middle - 5, body.bottom - 1),
          Offset(middle, size.height - .5),
          Offset(middle + 5, body.bottom - 1)
        ),
      AxisDirection.down => (
          Offset(middle - 5, body.top + 1),
          Offset(middle, .5),
          Offset(middle + 5, body.top + 1)
        ),
    };
    final pointer = Path()..addPolygon([a, b, c], true);
    final path = Path.combine(PathOperation.union, rounded, pointer);
    canvas.drawShadow(path, Colors.black54, 3, false);
    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(
        path,
        Paint()
          ..color = outline
          ..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(_BubbleBorder oldDelegate) =>
      side != oldDelegate.side ||
      tip != oldDelegate.tip ||
      fill != oldDelegate.fill ||
      outline != oldDelegate.outline;
}
