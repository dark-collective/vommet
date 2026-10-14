import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Vommet: a [SliverToBoxAdapter] that keeps what's on screen in place when
/// content above the visible top changes height (browser scroll anchoring).
///
/// The space room list is one box in the sidebar's scroll view. Without
/// this, someone joining or leaving a voice room that's scrolled out of view
/// adds or removes a participant row above the viewport, and every visible
/// room jumps. When the list is scrolled to its top nothing is held, so
/// changes there show as before.
class ScrollAnchoredBoxAdapter extends SingleChildRenderObjectWidget {
  const ScrollAnchoredBoxAdapter({super.key, super.child});

  @override
  RenderSliverToBoxAdapter createRenderObject(BuildContext context) =>
      RenderScrollAnchoredBoxAdapter();
}

class RenderScrollAnchoredBoxAdapter extends RenderSliverToBoxAdapter {
  /// Bounds the descent in [_findAnchor]; the room list is far shallower.
  static const int _maxDepth = 128;

  /// The deepest box under the first visible pixel at the last paint, and
  /// its top in the child's coordinates. Picked while painting because
  /// descendants' sizes can't be read during layout.
  RenderBox? _anchor;
  double _anchorTop = 0;

  @override
  void performLayout() {
    super.performLayout();

    final content = child;
    final anchor = _anchor;
    if (content == null || anchor == null || constraints.scrollOffset <= 0) {
      return;
    }
    final top = _topIn(anchor, content);
    if (top == null) {
      _anchor = null;
      return;
    }

    // Never scroll back past this sliver's own start.
    final correction = math.max(top - _anchorTop, -constraints.scrollOffset);
    // The viewport lays out again at the corrected offset; don't correct twice.
    _anchorTop = top;
    if (correction.abs() < 1e-6) return;
    geometry = SliverGeometry(scrollOffsetCorrection: correction);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);

    final content = child;
    _anchor = null;
    if (content == null || !content.hasSize || constraints.scrollOffset <= 0) {
      return;
    }
    final found =
        _findAnchor(content, constraints.scrollOffset + constraints.overlap);
    if (found != null) {
      _anchor = found.$1;
      _anchorTop = found.$2;
    }
  }

  @override
  void detach() {
    _anchor = null;
    super.detach();
  }

  static (RenderBox, double)? _findAnchor(RenderBox root, double y) {
    RenderObject node = root;
    var transform = Matrix4.identity();
    RenderBox? anchor;
    double anchorTop = 0;

    for (var depth = 0; depth < _maxDepth; depth++) {
      final parent = node;
      final parentTransform = transform;
      RenderBox? next;
      Matrix4? nextTransform;
      double nextTop = 0;

      parent.visitChildren((child) {
        if (next != null || child is! RenderBox || !child.hasSize) return;
        final childTransform = parentTransform.clone();
        parent.applyPaintTransform(child, childTransform);
        final rect =
            MatrixUtils.transformRect(childTransform, Offset.zero & child.size);
        if (rect.top <= y && rect.bottom > y) {
          next = child;
          nextTransform = childTransform;
          nextTop = rect.top;
        }
      });

      final found = next;
      if (found == null) break;
      anchor = found;
      anchorTop = nextTop;
      node = found;
      transform = nextTransform!;
    }

    if (anchor == null) return null;
    return (anchor, anchorTop);
  }

  /// [box]'s top in [root]'s coordinates, or null if the layout just removed
  /// it from under [root].
  static double? _topIn(RenderBox box, RenderBox root) {
    if (!box.attached) return null;
    RenderObject? node = box;
    while (node != null && node != root) {
      node = node.parent;
    }
    if (node == null) return null;
    return MatrixUtils.transformPoint(box.getTransformTo(root), Offset.zero).dy;
  }
}
