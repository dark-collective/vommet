import 'package:commet/debug/log.dart';
import 'package:flutter/material.dart';

class FloatingTile extends StatefulWidget {
  const FloatingTile(
      {super.key,
      required this.child,
      this.initialPosition = Alignment.topRight});
  final Alignment initialPosition;
  final Widget child;

  @override
  State<FloatingTile> createState() => _FloatingTileState();
}

class _FloatingTileState extends State<FloatingTile> {
  OverlayEntry? entry;

  @override
  void initState() {
    WidgetsBinding.instance.addPostFrameCallback((_) => addOverlay());
    super.initState();
  }

  @override
  void dispose() {
    Log.i("Floating tile is being diposed!");

    entry?.remove();
    super.dispose();
  }

  void addOverlay() {
    if (!mounted) return;
    Log.i("added floating tile overlay");

    entry = OverlayEntry(builder: buildOverlay);
    Overlay.of(context).insert(entry!);
  }

  Widget buildOverlay(BuildContext context) {
    return TileOverlay(
      initialPosition: widget.initialPosition,
      safeAreaPadding: MediaQuery.of(context).padding,
      child: widget.child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container();
  }
}

/// A tile that floats over the app, snapped to a corner. It can be dragged and
/// flung to another corner.
///
/// Vommet: the tile is anchored to its corner (an [Align]) rather than placed
/// by a top-left offset. Upstream measured the tile once and re-snapped it only
/// when the overlay rebuilt, so a label that grew afterwards (the sticker
/// import's "Uploading stickers: (3/120)") ran past the right edge, and it
/// divided the bounds by the app scale a second time. Now a growing tile
/// extends away from the edge it sits on, and never gets wider than the
/// window.
class TileOverlay extends StatefulWidget {
  const TileOverlay(
      {super.key,
      required this.child,
      this.initialPosition = Alignment.topRight,
      this.safeAreaPadding = EdgeInsets.zero});
  final EdgeInsets safeAreaPadding;
  final Alignment initialPosition;
  final Widget child;
  @override
  State<TileOverlay> createState() => _TileOverlayState();
}

class _TileOverlayState extends State<TileOverlay> {
  static const double margin = 10;

  late Alignment corner = _snap(widget.initialPosition);

  /// Where the tile is while it is being dragged.
  Alignment? dragAlignment;

  /// Where the pointer grabbed the tile, from its top-left.
  Offset grab = Offset.zero;

  final GlobalKey areaKey = GlobalKey();
  final GlobalKey childKey = GlobalKey();

  static Alignment _snap(Alignment a) =>
      Alignment(a.x < 0 ? -1 : 1, a.y < 0 ? -1 : 1);

  /// Free space the tile can move in, as (area, tile) sizes.
  (Size, Size)? _sizes() {
    final area = areaKey.currentContext?.size;
    final child = childKey.currentContext?.size;
    if (area == null || child == null) return null;
    return (area, child);
  }

  static double _toAxis(double pos, double free) =>
      free <= 0 ? 0 : (pos / free * 2 - 1).clamp(-1.0, 1.0);

  void onPanUpdate(DragUpdateDetails details) {
    final sizes = _sizes();
    final area = areaKey.currentContext?.findRenderObject() as RenderBox?;
    if (sizes == null || area == null) return;
    final (areaSize, childSize) = sizes;
    final topLeft = area.globalToLocal(details.globalPosition) - grab;
    setState(() {
      dragAlignment = Alignment(
          _toAxis(topLeft.dx, areaSize.width - childSize.width),
          _toAxis(topLeft.dy, areaSize.height - childSize.height));
    });
  }

  void onPanEnd(DragEndDetails details) {
    final current = dragAlignment ?? corner;
    final sizes = _sizes();
    var projected = current;
    if (sizes != null) {
      // Same fling as upstream: where the tile would be a second from now.
      final (areaSize, childSize) = sizes;
      final v = details.velocity.pixelsPerSecond;
      final freeX = areaSize.width - childSize.width;
      final freeY = areaSize.height - childSize.height;
      projected = Alignment(current.x + (freeX > 0 ? v.dx * 2 / freeX : 0),
          current.y + (freeY > 0 ? v.dy * 2 / freeY : 0));
    }
    setState(() {
      corner = _snap(projected);
      dragAlignment = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final dragging = dragAlignment != null;
    return Positioned.fill(
      child: Padding(
        padding: widget.safeAreaPadding + const EdgeInsets.all(margin),
        child: AnimatedAlign(
          key: areaKey,
          alignment: dragAlignment ?? corner,
          duration:
              dragging ? Duration.zero : const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (details) => grab = details.localPosition,
              onPanUpdate: onPanUpdate,
              onPanEnd: onPanEnd,
              child: Container(key: childKey, child: widget.child)),
        ),
      ),
    );
  }
}
