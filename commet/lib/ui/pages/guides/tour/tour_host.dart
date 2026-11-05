// Vommet issue 758: draws the Getting started tour above the whole app (and
// above menus, which are routes): the dim with a hole around the step's
// element, the bubble, the offer card and the paused tour's chip. Sits in
// MaterialApp's builder, so it covers every page.
import 'dart:math' as math;

import 'package:commet/config/platform_utils.dart';
import 'package:commet/ui/pages/guides/tour/tour.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

class TourHost extends StatefulWidget {
  const TourHost({required this.child, this.tour, this.touch, super.key});

  final Widget child;

  /// For tests; [Tour.instance] otherwise.
  final Tour? tour;

  /// For tests; phones and tablets use the tap/press-and-hold wording.
  final bool? touch;

  /// How long a step's element may be gone before the tour pauses.
  static const pauseAfter = Duration(milliseconds: 700);

  @override
  State<TourHost> createState() => _TourHostState();
}

class _TourHostState extends State<TourHost>
    with SingleTickerProviderStateMixin {
  final GlobalKey _stackKey = GlobalKey();
  late final Ticker _ticker = createTicker(_tick);
  Rect? _hole;
  Duration? _goneSince;

  Tour get tour => widget.tour ?? Tour.instance;

  bool get touch =>
      widget.touch ?? (PlatformUtils.isAndroid || PlatformUtils.isIOS);

  RenderBox? get _hostBox {
    final box = _stackKey.currentContext?.findRenderObject();
    return box is RenderBox && box.hasSize ? box : null;
  }

  @override
  void initState() {
    super.initState();
    tour.isVisible = (id) {
      final host = _hostBox;
      return host == null
          ? TourAnchors.has(id)
          : TourAnchors.rectOf(id, host) != null;
    };
    tour.addListener(_changed);
    _changed();
  }

  @override
  void dispose() {
    tour.removeListener(_changed);
    tour.isVisible = null;
    _ticker.dispose();
    super.dispose();
  }

  void _changed() {
    final running = tour.state == TourState.running;
    if (running && !_ticker.isActive) _ticker.start();
    if (!running && _ticker.isActive) _ticker.stop();
    _goneSince = null;
    _hole = running ? _measure() : null;
    if (mounted) setState(() {});
  }

  Rect? _measure() {
    final host = _hostBox;
    final anchor = tour.step.anchor;
    if (host == null || anchor == null) return null;
    return TourAnchors.rectOf(anchor, host);
  }

  /// Follows the element as it moves (scrolling, panels sliding) and pauses
  /// the tour when an element the step needs went away.
  void _tick(Duration elapsed) {
    if (tour.state != TourState.running) return;
    final hole = _measure();
    if (hole != null) {
      tour.elementSeen = true;
      _goneSince = null;
    } else if (tour.step.needsElement && tour.elementSeen) {
      _goneSince ??= elapsed;
      if (elapsed - _goneSince! >= TourHost.pauseAfter &&
          tour.step.kind != TourStepKind.untilGone) {
        tour.pause();
        return;
      }
    }
    if (hole != _hole) setState(() => _hole = hole);
    // An element can be added before it's laid out (a menu opening), so
    // steps waiting on one look again every frame.
    if (tour.step.kind == TourStepKind.untilAnchor ||
        tour.step.kind == TourStepKind.untilGone) {
      tour.anchorsChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = tour.state;
    final running = state == TourState.running;
    final step = running ? tour.step : null;
    final hole = running ? _hole : null;
    return Stack(
      key: _stackKey,
      fit: StackFit.expand,
      children: [
        widget.child,
        if (step != null)
          Positioned.fill(
            child: _TourBarrier(
              hole: hole?.inflate(_holePadding),
              block: step.blockOutside && hole != null,
            ),
          ),
        if (step != null && (step.dim || hole != null))
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _DimPainter(
                  hole: hole?.inflate(_holePadding),
                  dim: step.dim,
                  ring: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ),
        if (step != null)
          Positioned.fill(
            child: CustomSingleChildLayout(
              delegate: _BubbleLayout(hole?.inflate(_holePadding + 8)),
              child: _Bubble(
                tour: tour,
                step: step,
                touch: touch,
                onElement: hole != null,
              ),
            ),
          ),
        if (state == TourState.offering)
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Center(child: _OfferCard(tour: tour)),
          ),
        if (state == TourState.paused)
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Center(child: _ResumeChip(tour: tour)),
          ),
      ],
    );
  }

  static const _holePadding = 6.0;
}

/// Swallows taps outside [hole] while [block] is set, and lets everything
/// through otherwise, so the step's element is the only thing to press.
class _TourBarrier extends LeafRenderObjectWidget {
  const _TourBarrier({required this.hole, required this.block});

  final Rect? hole;
  final bool block;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderTourBarrier(hole, block);

  @override
  void updateRenderObject(
      BuildContext context, _RenderTourBarrier renderObject) {
    renderObject
      ..hole = hole
      ..block = block;
  }
}

class _RenderTourBarrier extends RenderBox {
  _RenderTourBarrier(this.hole, this.block);

  Rect? hole;
  bool block;

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!block || !size.contains(position)) return false;
    if (hole?.contains(position) ?? false) return false;
    result.add(BoxHitTestEntry(this, position));
    return true;
  }
}

class _DimPainter extends CustomPainter {
  _DimPainter({required this.hole, required this.dim, required this.ring});

  final Rect? hole;
  final bool dim;
  final Color ring;

  @override
  void paint(Canvas canvas, Size size) {
    final cut = hole == null
        ? null
        : RRect.fromRectAndRadius(hole!, const Radius.circular(10));
    if (dim) {
      final path = Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Offset.zero & size);
      if (cut != null) path.addRRect(cut);
      canvas.drawPath(path, Paint()..color = Colors.black.withAlpha(150));
    }
    if (cut != null) {
      canvas.drawRRect(
          cut,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = ring);
    }
  }

  @override
  bool shouldRepaint(_DimPainter old) =>
      old.hole != hole || old.dim != dim || old.ring != ring;
}

/// Puts the bubble beside the hole: right, left, below or above, whichever
/// fits first; in the middle when there's no hole.
class _BubbleLayout extends SingleChildLayoutDelegate {
  _BubbleLayout(this.hole);

  final Rect? hole;

  static const margin = 12.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(
          maxWidth: math.min(340, constraints.maxWidth - 2 * margin),
          maxHeight: constraints.maxHeight - 2 * margin);

  @override
  Offset getPositionForChild(Size size, Size child) =>
      bubblePosition(size, child, hole);

  @override
  bool shouldRelayout(_BubbleLayout old) => old.hole != hole;
}

/// Where a bubble of [child] size goes in [size] next to [hole].
@visibleForTesting
Offset bubblePosition(Size size, Size child, Rect? hole) {
  const m = _BubbleLayout.margin;
  double clampX(double x) =>
      x.clamp(m, math.max(m, size.width - child.width - m));
  double clampY(double y) =>
      y.clamp(m, math.max(m, size.height - child.height - m));
  if (hole == null) {
    return Offset((size.width - child.width) / 2,
        clampY((size.height - child.height) / 2));
  }
  if (hole.right + child.width + m <= size.width) {
    return Offset(hole.right, clampY(hole.top));
  }
  if (hole.left - child.width - m >= 0) {
    return Offset(hole.left - child.width, clampY(hole.top));
  }
  if (hole.bottom + child.height + m <= size.height) {
    return Offset(clampX(hole.left), hole.bottom);
  }
  if (hole.top - child.height - m >= 0) {
    return Offset(clampX(hole.left), hole.top - child.height);
  }
  return Offset(clampX((size.width - child.width) / 2),
      clampY(size.height - child.height - m));
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.tour,
    required this.step,
    required this.touch,
    required this.onElement,
  });

  final Tour tour;
  final TourStep step;
  final bool touch;
  final bool onElement;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = theme.colorScheme;
    final last = tour.index == tour.steps.length - 1;
    // Without its element on screen a step can't be done, so Next it is.
    final canNext = !step.needsElement || !onElement;
    return Material(
      key: const ValueKey("tour-bubble"),
      color: c.surfaceContainerHighest,
      elevation: 8,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tourStepOf(step.number, tour.total),
                style: theme.textTheme.labelSmall?.copyWith(color: c.primary)),
            const SizedBox(height: 4),
            Text(step.title(),
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Flexible(
              child: SingleChildScrollView(
                child: Text(step.body(touch),
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: c.onSurface)),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton(onPressed: tour.finish, child: Text(tourSkip)),
                if (tour.hasPrevious)
                  TextButton(onPressed: tour.back, child: Text(tourBack)),
                if (canNext || step.kind == TourStepKind.untilGuide)
                  FilledButton(
                    onPressed: tour.next,
                    child: Text(last ? tourDone : tourNext),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OfferCard extends StatelessWidget {
  const _OfferCard({required this.tour});

  final Tour tour;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = theme.colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Material(
        key: const ValueKey("tour-offer"),
        color: c.surfaceContainerHighest,
        elevation: 8,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tourOfferTitle,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(tourOfferBody,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: c.onSurfaceVariant)),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: tour.decline, child: Text(tourNotNow)),
                  const SizedBox(width: 4),
                  FilledButton(onPressed: tour.start, child: Text(tourStart)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResumeChip extends StatelessWidget {
  const _ResumeChip({required this.tour});

  final Tour tour;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Material(
      key: const ValueKey("tour-resume"),
      color: c.surfaceContainerHighest,
      elevation: 6,
      shape: StadiumBorder(side: BorderSide(color: c.primary, width: 1.5)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            customBorder: const StadiumBorder(),
            onTap: tour.resume,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
              child: Text(tourResume(tour.step.number, tour.total),
                  style: TextStyle(
                      color: c.onSurface, fontWeight: FontWeight.w600)),
            ),
          ),
          // No tooltip: the host sits above the Navigator, so there's no
          // Overlay for one.
          Semantics(
            label: tourEnd,
            button: true,
            child: IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: tour.finish,
            ),
          ),
        ],
      ),
    );
  }
}
