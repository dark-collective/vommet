import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Vommet issue 897: a scroll controller whose scroll view can be put back
/// in place in the same frame as its content reflows ([anchor]). Jumping
/// after the frame instead showed one frame at the old offset, so the grid
/// flickered as it was resized.
class ReflowScrollController extends ScrollController {
  ReflowScrollController({super.debugLabel});

  /// At the scroll view's next layout, once it knows how tall its content
  /// is (`extent`, the viewport included), scrolls to `pixels(extent)`
  /// (within its scroll range) before anything is painted. Forgotten after
  /// this frame if nothing was laid out.
  void anchor(double Function(double extent) pixels) {
    for (final position in positions) {
      if (position is _ReflowScrollPosition) position._anchor = pixels;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final position in positions) {
        if (position is _ReflowScrollPosition) position._anchor = null;
      }
    });
  }

  @override
  ScrollPosition createScrollPosition(ScrollPhysics physics,
          ScrollContext context, ScrollPosition? oldPosition) =>
      _ReflowScrollPosition(
          physics: physics,
          context: context,
          initialPixels: initialScrollOffset,
          keepScrollOffset: keepScrollOffset,
          oldPosition: oldPosition,
          debugLabel: debugLabel);
}

class _ReflowScrollPosition extends ScrollPositionWithSingleContext {
  _ReflowScrollPosition(
      {required super.physics,
      required super.context,
      super.initialPixels,
      super.keepScrollOffset,
      super.oldPosition,
      super.debugLabel});

  double Function(double extent)? _anchor;

  @override
  bool applyContentDimensions(double minScrollExtent, double maxScrollExtent) {
    final anchor = _anchor;
    if (anchor != null && hasViewportDimension) {
      _anchor = null;
      final extent = maxScrollExtent - minScrollExtent + viewportDimension;
      final target = math.max(minScrollExtent,
          math.min(anchor(extent), math.max(minScrollExtent, maxScrollExtent)));
      if ((target - pixels).abs() > precisionErrorTolerance) {
        // The viewport lays out again at the new offset.
        correctPixels(target);
        // Listeners (the scrollbar, loading more) hear of it after the frame,
        // as they would of a jump.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (hasListeners) notifyListeners();
        });
        return false;
      }
    }
    return super.applyContentDimensions(minScrollExtent, maxScrollExtent);
  }
}
