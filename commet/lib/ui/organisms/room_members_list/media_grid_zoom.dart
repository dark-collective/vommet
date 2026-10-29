import 'dart:math' as math;

import 'package:commet/config/preferences/double_preference.dart';
import 'package:commet/main.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// A grid whose thumbnail size Ctrl + mouse wheel (or a pinch on a touch
/// screen) steps through [sizes], remembered in [preference]
/// ([MediaGridZoomDetector]). Vommet issue 790: the Media tab
/// ([MediaGridZoom.zoom]) and the sticker picker ([stickers]) each have one.
class GridZoom {
  GridZoom(
      {required this.sizes,
      required DoublePreference Function() preference,
      this.fixedCount = false})
      : _preference = preference;

  /// The sizes a step moves between, in logical pixels.
  final List<double> sizes;

  final DoublePreference Function() _preference;

  /// Whether the grid fits `floor(width / size)` items per row
  /// (SliverGridDelegateWithFixedCrossAxisCount, as the emoji picker lays
  /// out) rather than treating the size as the widest item
  /// (SliverGridDelegateWithMaxCrossAxisExtent, as the Media tab does).
  final bool fixedCount;

  DoublePreference get preference => _preference();

  double get size => preference.value;

  void set(double next) {
    if (next != size) preference.set(next);
  }

  /// Vommet issue 790: the sticker picker's sticker size, 125 (its old fixed
  /// size) until the user resizes it.
  static final stickers = GridZoom(
      sizes: const [64, 80, 96, 110, 125, 150, 180, 230, 280],
      preference: () => preferences.stickerPickerSize,
      fixedCount: true);

  /// The size one step bigger ([direction] 1) or smaller (-1) than
  /// [current], which need not be one of [sizes].
  double step(double current, int direction) {
    var nearest = 0;
    for (var i = 1; i < sizes.length; i++) {
      if ((sizes[i] - current).abs() < (sizes[nearest] - current).abs()) {
        nearest = i;
      }
    }
    final index = (nearest + direction).clamp(0, sizes.length - 1);
    return sizes[index];
  }

  void stepBy(int direction) => set(step(size, direction));

  /// The size a pinch that ended at [scale] (fingers' spread now / at the
  /// start) settles on from [current]: the nearest of [sizes] to what the
  /// thumbnails looked like, and at least one step once the pinch passed
  /// [MediaGridZoom.settleThreshold] either way.
  double settle(double current, double scale) {
    final target = current * scale;
    var best = sizes.first;
    for (final s in sizes) {
      if ((math.log(s / target)).abs() < (math.log(best / target)).abs()) {
        best = s;
      }
    }
    if (best == step(current, 0)) {
      if (scale >= MediaGridZoom.settleThreshold) return step(current, 1);
      if (scale <= 1 / MediaGridZoom.settleThreshold) return step(current, -1);
    }
    return best;
  }

  /// The size to lay the grid out at mid-pinch: what [settle] would pick for
  /// a pinch that started at [origin] and is now at [scale], unless the grid
  /// is already at [current] and the pinch is still within
  /// [MediaGridZoom.liveHysteresis] of where [current] would be picked.
  double live(double origin, double current, double scale) {
    final next = settle(origin, scale);
    if (next == current) return current;
    const h = MediaGridZoom.liveHysteresis;
    if (settle(origin, scale * h) == current ||
        settle(origin, scale / h) == current) {
      return current;
    }
    return next;
  }

  /// An item's actual width in a grid [width] wide laid out at [extent].
  double tileWidth(double extent, double width) {
    if (!fixedCount) return MediaGridZoom.tileWidth(extent, width);
    if (width <= 0) return extent;
    return width / (width / extent).floor().clamp(1, 1 << 20);
  }
}

/// Vommet issue 622: the Media tab's thumbnail size, which Ctrl + mouse
/// wheel (or a pinch on a touch screen) steps through. Remembered on this
/// device for every room ([VommetPreferences.mediaGridThumbnailSize]).
class MediaGridZoom {
  /// The sizes a step moves between, in logical pixels (the grid's widest
  /// thumbnail; the grid fits as many per row as that allows).
  static const sizes = <double>[64, 80, 96, 110, 140, 180, 230, 280, 320];

  static final zoom = GridZoom(
      sizes: sizes, preference: () => preferences.mediaGridThumbnailSize);

  static double get size => preferences.mediaGridThumbnailSize.value;

  /// The size one step bigger ([direction] 1) or smaller (-1) than
  /// [current], which need not be one of [sizes].
  static double step(double current, int direction) =>
      zoom.step(current, direction);

  static void stepBy(int direction) => zoom.stepBy(direction);

  /// Vommet issue 649: how far a pinch must spread (or close) to change the
  /// size at all when it lets go.
  static const settleThreshold = 1.15;

  /// See [GridZoom.settle].
  static double settle(double current, double scale) =>
      zoom.settle(current, scale);

  /// Vommet issue 682: how far past a size boundary a pinch must go before
  /// the grid re-lays out mid-pinch, and how far back before it returns, so
  /// fingers resting right on a boundary don't make it flicker.
  static const liveHysteresis = 1.05;

  /// See [GridZoom.live].
  static double live(double origin, double current, double scale) =>
      zoom.live(origin, current, scale);

  /// A thumbnail's actual width in a grid [width] wide whose widest
  /// thumbnail is [extent], as SliverGridDelegateWithMaxCrossAxisExtent
  /// lays it out.
  static double tileWidth(double extent, double width, {double spacing = 4}) {
    if (width <= 0) return extent;
    final count = (width / (extent + spacing)).ceil().clamp(1, 1 << 20);
    return (width - spacing * (count - 1)) / count;
  }
}

/// Lets a scroll view ignore the mouse wheel while Ctrl is held, so
/// [MediaGridZoomDetector] above it gets the wheel instead.
class NoWheelWhileCtrlScrollPhysics extends ScrollPhysics {
  const NoWheelWhileCtrlScrollPhysics({super.parent});

  @override
  NoWheelWhileCtrlScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      NoWheelWhileCtrlScrollPhysics(parent: buildParent(ancestor));

  @override
  bool shouldAcceptUserOffset(ScrollMetrics position) =>
      !HardwareKeyboard.instance.isControlPressed &&
      super.shouldAcceptUserOffset(position);
}

/// Resizes the Media tab's thumbnails: Ctrl + wheel up makes them bigger,
/// Ctrl + wheel down smaller; on a touch screen two fingers pinching apart
/// or together do the same. The scroll view below must use
/// [NoWheelWhileCtrlScrollPhysics].
///
/// Vommet issue 649: while two fingers pinch, the whole grid zooms with them
/// around the point between them; when they let go it settles on the
/// nearest size ([MediaGridZoom.settle]) with a short animation. A Ctrl +
/// wheel step animates the same way. With [controller], the spot under the
/// fingers (or the pointer) stays roughly where it was after the reflow.
///
/// Vommet issue 682: the grid re-lays out during the pinch too, as soon as
/// the pinch passes the next size ([MediaGridZoom.live]), so the thumbnails
/// per row always show what letting go would settle on; the zoom carries on
/// from the new layout without a jump.
///
/// Vommet issue 790: [zoom] picks the grid (the Media tab's by default).
class MediaGridZoomDetector extends StatefulWidget {
  const MediaGridZoomDetector(
      {required this.child,
      this.controller,
      this.padding = 8,
      this.zoom,
      super.key});
  final Widget child;

  /// The grid's sizes and remembered size; null for the Media tab's.
  final GridZoom? zoom;

  /// The grid's scroll view, to keep its place across a size change.
  final ScrollController? controller;

  /// The grid's padding on each side, to work out the thumbnails' width.
  final double padding;

  @override
  State<MediaGridZoomDetector> createState() => _MediaGridZoomDetectorState();
}

class _MediaGridZoomDetectorState extends State<MediaGridZoomDetector>
    with SingleTickerProviderStateMixin {
  GridZoom get _zoom => widget.zoom ?? MediaGridZoom.zoom;

  /// Wheel distance since the last step; a mouse notch is one step, a
  /// trackpad's many small deltas add up to one.
  double _wheel = 0;
  static const _wheelPerStep = 50.0;

  final Map<int, Offset> _touches = {};
  double? _pinchStart;

  /// The thumbnail size when the pinch started.
  double _pinchOrigin = 0;

  /// The zoom the layout at the current size needs on top of the pinch's own
  /// scale to look the same as before the pinch re-laid it out.
  double _rebase = 1;

  /// The grid's zoom while two fingers pinch (1 = as laid out).
  double _live = 1;

  /// Where the zoom is centred, in this widget's coordinates.
  Offset _focal = Offset.zero;

  /// After a size change: from [_settleFrom] (what the new layout must be
  /// zoomed by to look like the old one) back to 1.
  late final AnimationController _settle;
  double _settleFrom = 1;

  @override
  void initState() {
    super.initState();
    _settle = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 220), value: 1)
      ..addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  double get _scale {
    if (_pinchStart != null) return _live;
    final t = Curves.easeOutCubic.transform(_settle.value);
    return _settleFrom + (1 - _settleFrom) * t;
  }

  /// Animates from the grid zoomed by [from] to its layout.
  void _animateFrom(double from) {
    if (MediaQuery.maybeDisableAnimationsOf(context) == true || from == 1) {
      _settleFrom = 1;
      _settle.value = 1;
      return;
    }
    _settleFrom = from;
    _settle.forward(from: 0);
  }

  /// Sets the thumbnail size to [next], the grid currently zoomed by [shown]
  /// around [_focal], and animates into the new layout.
  void _resize(double next, double shown) =>
      _animateFrom(shown * _relayout(next));

  /// Sets the thumbnail size to [next], keeping the spot at [_focal] in
  /// place, and returns what the new layout must be zoomed by to look like
  /// the old one.
  double _relayout(double next) {
    final current = _zoom.size;
    final box = context.findRenderObject() as RenderBox?;
    final width = (box?.size.width ?? 0) - 2 * widget.padding;
    final before = _zoom.tileWidth(current, width);
    final after = _zoom.tileWidth(next, width);

    // Where the focal point sits in the whole scrolled content, as a share
    // of it, to put it back there once the grid has reflowed.
    final controller = widget.controller;
    double? share;
    if (controller != null && controller.hasClients) {
      final position = controller.position;
      final total = position.maxScrollExtent + position.viewportDimension;
      if (total > 0) share = (position.pixels + _focal.dy) / total;
    }

    _zoom.set(next);

    if (share != null) {
      final focalY = _focal.dy;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || controller == null || !controller.hasClients) return;
        final position = controller.position;
        final total = position.maxScrollExtent + position.viewportDimension;
        controller.jumpTo((share! * total - focalY)
            .clamp(position.minScrollExtent, position.maxScrollExtent));
      });
    }
    return after > 0 ? before / after : 1;
  }

  void _onSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent ||
        !HardwareKeyboard.instance.isControlPressed) {
      return;
    }
    GestureBinding.instance.pointerSignalResolver.register(event, (event) {
      final dy = (event as PointerScrollEvent).scrollDelta.dy;
      if (dy == 0) return;
      // A change of direction starts counting again.
      if (_wheel.sign != dy.sign) _wheel = 0;
      _wheel += dy;
      if (_wheel.abs() >= _wheelPerStep) {
        // Wheel up (negative) = bigger.
        final next = _zoom.step(_zoom.size, _wheel < 0 ? 1 : -1);
        _wheel = 0;
        if (next == _zoom.size) return;
        _focal = event.localPosition;
        _resize(next, _scale);
      }
    });
  }

  double? get _spread {
    if (_touches.length != 2) return null;
    final points = _touches.values.toList();
    return (points[0] - points[1]).distance;
  }

  Offset? get _midpoint {
    if (_touches.length != 2) return null;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return null;
    final points = _touches.values.toList();
    return box.globalToLocal((points[0] + points[1]) / 2);
  }

  void _onDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.touch) return;
    _touches[event.pointer] = event.position;
    final spread = _spread;
    if (spread != null && spread > 0) {
      // A second finger: the pinch starts from whatever is on screen now.
      _live = _scale;
      _settle.stop();
      _settleFrom = 1;
      _settle.value = 1;
      _pinchStart = spread / _live;
      _pinchOrigin = _zoom.size;
      _rebase = 1;
      _focal = _midpoint ?? _focal;
      setState(() {});
    }
  }

  void _onMove(PointerMoveEvent event) {
    if (!_touches.containsKey(event.pointer)) return;
    _touches[event.pointer] = event.position;
    final start = _pinchStart, spread = _spread;
    if (start == null || spread == null || start <= 0) return;
    final origin = _pinchOrigin;
    // A little past the smallest and biggest sizes, so the ends still give
    // way under the fingers.
    final scale = (spread / start).clamp(
        _zoom.sizes.first * 0.85 / origin, _zoom.sizes.last * 1.15 / origin);
    _focal = _midpoint ?? _focal;
    final size = _zoom.size;
    final next = _zoom.live(origin, size, scale);
    if (next != size) _rebase *= _relayout(next);
    _live = scale * _rebase;
    setState(() {});
  }

  void _onUp(PointerEvent event) {
    if (_touches.remove(event.pointer) == null) return;
    if (_pinchStart == null) return;
    // One finger left the pinch: the grid is already laid out at the size
    // the pinch picked, so just ease the zoom back to it.
    final shown = _live;
    _pinchStart = null;
    _live = 1;
    _rebase = 1;
    _animateFrom(shown);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = _scale, f = _focal;
    return Listener(
      onPointerSignal: _onSignal,
      onPointerDown: _onDown,
      onPointerMove: _onMove,
      onPointerUp: _onUp,
      onPointerCancel: _onUp,
      child: ClipRect(
        // Always a Transform, so the scroll view below keeps its state.
        child: Transform(
          transform: Matrix4(s, 0, 0, 0, 0, s, 0, 0, 0, 0, 1, 0, (1 - s) * f.dx,
              (1 - s) * f.dy, 0, 1),
          child: widget.child,
        ),
      ),
    );
  }
}
