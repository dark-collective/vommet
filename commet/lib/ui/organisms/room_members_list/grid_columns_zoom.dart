import 'dart:math' as math;

import 'package:commet/config/build_config.dart';
import 'package:commet/ui/organisms/room_members_list/media_grid_zoom.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Vommet issue 897: a grid of square items, [columns] per row, which need
/// not be a whole number. Between n and n + 1 per row every item is part of
/// the way from its place at n per row to its place at n + 1, and its size
/// part of the way between the two ([ColumnsGridLayout]), so a pinch moves
/// the stickers smoothly from one layout to the next.
class SliverGridDelegateWithColumns extends SliverGridDelegate {
  const SliverGridDelegateWithColumns(this.columns);

  final double columns;

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) =>
      ColumnsGridLayout(columns, constraints.crossAxisExtent,
          reverseCrossAxis:
              axisDirectionIsReversed(constraints.crossAxisDirection));

  @override
  bool shouldRelayout(SliverGridDelegateWithColumns oldDelegate) =>
      oldDelegate.columns != columns;
}

/// See [SliverGridDelegateWithColumns]. Items are `width / columns` wide;
/// their places are the same share of the way between the two whole-number
/// layouts as their size.
class ColumnsGridLayout extends SliverGridLayout {
  factory ColumnsGridLayout(double columns, double width,
      {bool reverseCrossAxis = false}) {
    final count = math.max(1, columns.floor());
    final from = _regular(count, width, reverseCrossAxis);
    final t = progress(columns);
    if (t == 0) return ColumnsGridLayout._(from, from, 0);
    return ColumnsGridLayout._(
        from, _regular(count + 1, width, reverseCrossAxis), t);
  }

  const ColumnsGridLayout._(this._from, this._to, this._t);

  final SliverGridRegularTileLayout _from;
  final SliverGridRegularTileLayout _to;
  final double _t;

  /// How far [columns] is from `floor(columns)` per row (0) to one more
  /// (1), measured by item size: `width / columns` is that share of the way
  /// from `width / n` to `width / (n + 1)`.
  static double progress(double columns) {
    final n = columns.floor();
    if (n < 1 || columns <= n) return 0;
    return ((n + 1) * (columns - n) / columns).clamp(0.0, 1.0);
  }

  static SliverGridRegularTileLayout _regular(
      int count, double width, bool reverseCrossAxis) {
    final extent = math.max(0.0, width) / count;
    return SliverGridRegularTileLayout(
        crossAxisCount: count,
        mainAxisStride: extent,
        crossAxisStride: extent,
        childMainAxisExtent: extent,
        childCrossAxisExtent: extent,
        reverseCrossAxis: reverseCrossAxis);
  }

  double _lerp(double a, double b) => a + (b - a) * _t;

  // Both layouts keep items in index order down the grid, and a blend of
  // the two does too, so the first item that can show is the earlier of
  // the two layouts' first, and the last the later of their last.
  @override
  int getMinChildIndexForScrollOffset(double scrollOffset) => math.min(
      _from.getMinChildIndexForScrollOffset(scrollOffset),
      _to.getMinChildIndexForScrollOffset(scrollOffset));

  @override
  int getMaxChildIndexForScrollOffset(double scrollOffset) => math.max(
      _from.getMaxChildIndexForScrollOffset(scrollOffset),
      _to.getMaxChildIndexForScrollOffset(scrollOffset));

  @override
  SliverGridGeometry getGeometryForChildIndex(int index) {
    final a = _from.getGeometryForChildIndex(index);
    if (_t == 0) return a;
    final b = _to.getGeometryForChildIndex(index);
    return SliverGridGeometry(
        scrollOffset: _lerp(a.scrollOffset, b.scrollOffset),
        crossAxisOffset: _lerp(a.crossAxisOffset, b.crossAxisOffset),
        mainAxisExtent: _lerp(a.mainAxisExtent, b.mainAxisExtent),
        crossAxisExtent: _lerp(a.crossAxisExtent, b.crossAxisExtent));
  }

  @override
  double computeMaxScrollOffset(int childCount) {
    if (childCount <= 0) return 0;
    return _lerp(_from.computeMaxScrollOffset(childCount),
        _to.computeMaxScrollOffset(childCount));
  }

  /// The item of [count] at [position] (across, down) in the grid, or the
  /// nearest one to it.
  int indexAt(Offset position, int count) {
    if (count <= 0) return 0;
    final first =
        getMinChildIndexForScrollOffset(position.dy).clamp(0, count - 1);
    final last =
        getMaxChildIndexForScrollOffset(position.dy).clamp(first, count - 1);
    var best = first;
    var bestDistance = double.infinity;
    for (var i = first; i <= last; i++) {
      final g = getGeometryForChildIndex(i);
      final rect = Rect.fromLTWH(g.crossAxisOffset, g.scrollOffset,
          g.crossAxisExtent, g.mainAxisExtent);
      if (rect.contains(position)) return i;
      final distance = (rect.center - position).distanceSquared;
      if (distance < bestDistance) {
        best = i;
        bestDistance = distance;
      }
    }
    return best;
  }
}

/// Vommet issue 897: resizes a [GridZoom.fixedCount] grid (the sticker
/// picker) one item per row at a time. Ctrl + wheel up shows one fewer per
/// row (bigger), down one more; two fingers pinching apart or together do
/// the same, the layout following the fingers between two counts
/// ([SliverGridDelegateWithColumns]) and easing into the nearer one when
/// they let go ([GridZoom.settleColumns]). A wheel step eases the same way.
/// Past the fewest or the most per row the grid gives a little under the
/// fingers and springs back. The scroll view inside must use
/// [NoWheelWhileCtrlScrollPhysics].
///
/// On a phone held sideways items are [GridZoom.landscapeScale] times the
/// remembered size.
class GridColumnsZoom extends StatefulWidget {
  const GridColumnsZoom(
      {required this.zoom, required this.builder, this.onFocus, super.key});

  final GridZoom zoom;

  /// Builds the grid at `columns` per row: a whole number at rest, between
  /// two while a pinch or a step is under way.
  final Widget Function(
      BuildContext context, BoxConstraints constraints, double columns) builder;

  /// Where a pinch or a Ctrl + wheel step is centered when it starts (in
  /// this widget), so the grid can keep what is there in place while it
  /// reflows; null after the frame it settles in.
  final ValueChanged<Offset?>? onFocus;

  @override
  State<GridColumnsZoom> createState() => _GridColumnsZoomState();
}

class _GridColumnsZoomState extends State<GridColumnsZoom>
    with SingleTickerProviderStateMixin {
  GridZoom get _zoom => widget.zoom;

  double _width = 0;
  double _scale = 1;

  /// Wheel distance since the last step, as in [MediaGridZoomDetector].
  double _wheel = 0;
  static const _wheelPerStep = 50.0;

  final Map<int, Offset> _touches = {};
  double? _pinchStart;

  /// The items per row shown when the pinch started.
  double _pinchColumns = 1;

  /// The items per row the pinch shows now.
  double _pinch = 1;

  /// How much the grid is zoomed past the fewest or the most per row.
  double _edge = 1;

  /// Where the zoom is centred, in this widget's coordinates.
  Offset _focal = Offset.zero;

  /// After a pinch or a step: from [_fromColumns] (and [_fromEdge]) to the
  /// size just remembered.
  late final AnimationController _settle;
  double _fromColumns = 1;
  double _fromEdge = 1;
  int _toColumns = 1;

  @override
  void initState() {
    super.initState();
    _settle = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 220), value: 1)
      ..addListener(() => setState(() {}))
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _settled();
      });
    _zoom.changes.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(GridColumnsZoom oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.zoom != widget.zoom) {
      oldWidget.zoom.changes.removeListener(_onChanged);
      widget.zoom.changes.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    _zoom.changes.removeListener(_onChanged);
    _settle.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  int get _rest => _zoom.columns(_width, scale: _scale);

  bool get _settling => _settle.isAnimating;

  double get _columns {
    if (_pinchStart != null) return _pinch;
    if (!_settling) return _rest.toDouble();
    final t = Curves.easeOutCubic.transform(_settle.value);
    return _fromColumns + (_toColumns - _fromColumns) * t;
  }

  double get _shownEdge {
    if (_pinchStart != null) return _edge;
    if (!_settling) return 1;
    final t = Curves.easeOutCubic.transform(_settle.value);
    return _fromEdge + (1 - _fromEdge) * t;
  }

  /// Remembers [columns] per row and eases into it from [from] per row
  /// zoomed by [edge] (what is shown, by default).
  void _settleInto(int columns, {double? from, double? edge}) {
    from ??= _columns;
    edge ??= _shownEdge;
    _zoom.set(_zoom.sizeFor(_width, columns, scale: _scale));
    _fromColumns = from;
    _fromEdge = edge;
    _toColumns = columns;
    if (MediaQuery.maybeDisableAnimationsOf(context) == true ||
        (from == columns && edge == 1)) {
      _settle.value = 1;
      setState(() {});
      _settled();
      return;
    }
    _settle.forward(from: 0);
  }

  /// The grid is at rest: no more focus once this frame is laid out.
  void _settled() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _pinchStart != null || _settling) return;
      widget.onFocus?.call(null);
    });
  }

  void _onSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent ||
        !HardwareKeyboard.instance.isControlPressed) {
      return;
    }
    GestureBinding.instance.pointerSignalResolver.register(event, (event) {
      final dy = (event as PointerScrollEvent).scrollDelta.dy;
      if (dy == 0 || _pinchStart != null) return;
      if (_wheel.sign != dy.sign) _wheel = 0;
      _wheel += dy;
      if (_wheel.abs() < _wheelPerStep) return;
      // Wheel up (negative) = bigger, one fewer per row. Steps while one
      // is easing in count on from where it is going.
      final from = _settling ? _toColumns : _rest;
      final next = _zoom.stepColumns(from, _wheel < 0 ? 1 : -1, _width);
      _wheel = 0;
      if (next == from) return;
      _focal = event.localPosition;
      widget.onFocus?.call(_focal);
      _settleInto(next);
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
    if (spread == null || spread <= 0) return;
    // A second finger: the pinch starts from whatever is on screen now.
    _pinchColumns = _pinch = _columns;
    _edge = 1;
    _settle.stop();
    _settle.value = 1;
    _pinchStart = spread;
    _focal = _midpoint ?? _focal;
    widget.onFocus?.call(_focal);
    setState(() {});
  }

  void _onMove(PointerMoveEvent event) {
    if (!_touches.containsKey(event.pointer)) return;
    _touches[event.pointer] = event.position;
    final start = _pinchStart, spread = _spread;
    if (start == null || spread == null || start <= 0 || spread <= 0) return;
    // Fingers twice as far apart = items twice as big = half as many per
    // row.
    final wanted = _pinchColumns * start / spread;
    _pinch = wanted.clamp(_zoom.minColumns(_width).toDouble(),
        _zoom.maxColumns(_width).toDouble());
    _edge = math.sqrt(_pinch / wanted).clamp(0.85, 1.15);
    setState(() {});
  }

  void _onUp(PointerEvent event) {
    if (_touches.remove(event.pointer) == null) return;
    if (_pinchStart == null) return;
    // One finger left: ease from what the pinch showed into the count it
    // settles on.
    final settled = GridZoom.settleColumns(_pinchColumns, _pinch)
        .clamp(_zoom.minColumns(_width), _zoom.maxColumns(_width));
    final from = _pinch, edge = _edge;
    _pinchStart = null;
    _edge = 1;
    _settleInto(settled, from: from, edge: edge);
  }

  @override
  Widget build(BuildContext context) {
    _scale = GridZoom.landscapeScale(MediaQuery.sizeOf(context),
        mobile: BuildConfig.MOBILE);
    return Listener(
      onPointerSignal: _onSignal,
      onPointerDown: _onDown,
      onPointerMove: _onMove,
      onPointerUp: _onUp,
      onPointerCancel: _onUp,
      child: ClipRect(
        child: LayoutBuilder(builder: (context, constraints) {
          _width = constraints.maxWidth;
          final s = _shownEdge, f = _focal;
          // Always a Transform, so the scroll view below keeps its state.
          return Transform(
            transform: Matrix4(s, 0, 0, 0, 0, s, 0, 0, 0, 0, 1, 0,
                (1 - s) * f.dx, (1 - s) * f.dy, 0, 1),
            child: widget.builder(context, constraints, _columns),
          );
        }),
      ),
    );
  }
}
