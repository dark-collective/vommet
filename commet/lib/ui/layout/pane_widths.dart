import 'package:commet/config/preferences/double_preference.dart';
import 'package:commet/main.dart';
import 'package:flutter/material.dart';

/// Vommet: a resizable desktop pane's width. Follows drags live and is saved
/// when the drag ends.
class PaneWidth extends ValueNotifier<double> {
  PaneWidth(this.preference, {this.min = 180, this.max = 480})
      : super(preference.value.clamp(min, max));

  final DoublePreference preference;
  final double min;
  final double max;

  double get defaultValue => preference.defaultValue;

  /// The width to lay out with: the dragged one while the Discord-style
  /// layout experiment is on, otherwise the default.
  double get effective =>
      preferences.experimentBannerLayout.value ? value : defaultValue;

  static bool get resizable => preferences.experimentBannerLayout.value;

  /// Within this distance of the default, a drag sticks to the default.
  static const snap = 10.0;

  // Where the pointer has dragged the edge, before snapping, so a drag can
  // pull back out of the snap zone.
  double? _dragged;

  void drag(double delta) {
    final dragged = ((_dragged ?? value) + delta).clamp(min, max);
    _dragged = dragged;
    value = (dragged - defaultValue).abs() <= snap ? defaultValue : dragged;
  }

  /// Ends a drag: keeps the (possibly snapped) width.
  Future<void> save() {
    _dragged = null;
    return preference.set(value);
  }

  Future<void> reset() {
    _dragged = null;
    value = defaultValue;
    return preference.set(defaultValue);
  }
}

/// The two resizable panes either side of the chat.
class PaneWidths {
  /// The space/room list beside the space bar.
  static final left = PaneWidth(preferences.leftPaneWidth);

  /// The room's side panel (banner and member list).
  static final right = PaneWidth(preferences.rightPaneWidth);
}

/// A thin grab strip on a pane's edge: drag to resize, double-click to reset.
class PaneResizeHandle extends StatelessWidget {
  const PaneResizeHandle(this.pane, {this.growsRight = true, super.key});

  final PaneWidth pane;

  /// True when dragging right widens the pane (the left pane's right edge).
  final bool growsRight;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: "Drag to resize, double-click to reset",
      waitDuration: const Duration(seconds: 1),
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (d) =>
              pane.drag(growsRight ? d.delta.dx : -d.delta.dx),
          onHorizontalDragEnd: (_) => pane.save(),
          onDoubleTap: pane.reset,
          child: const SizedBox(width: 6, height: double.infinity),
        ),
      ),
    );
  }
}
