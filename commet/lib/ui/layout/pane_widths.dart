import 'package:commet/config/preferences/double_preference.dart';
import 'package:commet/main.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:commet/config/room_layout_options.dart';

/// Vommet: a resizable desktop pane's width. Follows drags live and is saved
/// when the drag ends.
class PaneWidth extends ValueNotifier<double> {
  PaneWidth(this.preference,
      {this.min = 180, this.max = 480, bool Function()? resizableWhen})
      : _resizableWhen = resizableWhen ?? _bannerLayout,
        super(preference.value.clamp(min, max));

  final DoublePreference preference;
  final double min;
  final double max;

  double get defaultValue => preference.defaultValue;

  final bool Function() _resizableWhen;

  static bool _bannerLayout() => resizablePanels.value;

  /// Whether the pane can be dragged now: by default while Resize panels
  /// (Settings › Appearance › Layout) is on.
  bool get resizable => _resizableWhen();

  /// The width to lay out with: the dragged one while [resizable], otherwise
  /// the default.
  double get effective => resizable ? value : defaultValue;

  /// Within this distance of the default, a drag sticks to the default.
  static const snap = 10.0;

  /// Vommet issue 456: pulled this far past [min], letting go collapses
  /// the pane (where it can be; see [PaneResizeHandle.onCollapse]).
  static const collapsePull = 60.0;

  /// True while a drag holds the edge [collapsePull] or more past [min].
  final pulledPastMin = ValueNotifier<bool>(false);

  // Where the pointer has dragged the edge, before snapping and clamping, so
  // a drag can pull back out of the snap zone or from past a limit.
  double? _dragged;

  // The width when the drag started, kept when it collapses the pane.
  double? _start;

  void drag(double delta) {
    _start ??= value;
    final dragged = (_dragged ?? value) + delta;
    _dragged = dragged;
    pulledPastMin.value = dragged <= min - collapsePull;
    final width = dragged.clamp(min, max);
    value = (width - defaultValue).abs() <= snap ? defaultValue : width;
  }

  /// Ends a drag: keeps the (possibly snapped) width.
  Future<void> save() {
    _endDrag();
    return preference.set(value);
  }

  /// Ends a drag that collapsed the pane: back to the width it started at,
  /// for when it's widened again.
  void endCollapsed() {
    value = _start ?? value;
    _endDrag();
  }

  void _endDrag() {
    _dragged = null;
    _start = null;
    pulledPastMin.value = false;
  }

  Future<void> reset() {
    _endDrag();
    value = defaultValue;
    return preference.set(defaultValue);
  }
}

/// Vommet issue 747: a pane whose dragged width is kept as a share of the
/// area it sits in, so it scales with the window. The layout sets [area]
/// before the pane is sized; until the pane is first dragged it follows
/// [seed]'s width in pixels.
class SharePaneWidth extends PaneWidth {
  SharePaneWidth(this.share, this.seed)
      : super(seed.preference,
            min: seed.min, max: seed.max, resizableWhen: () => seed.resizable);

  /// The saved width over [area]; 0 until first dragged.
  final DoublePreference share;
  final PaneWidth seed;

  /// The width of the area the pane sits in, from the last layout.
  double? area;

  @override
  double get effective {
    if (!resizable) return defaultValue;
    final area = this.area;
    // While dragging, the pane follows the pointer.
    if (_start != null || area == null || area <= 0) return value;
    final share = this.share.value;
    if (share <= 0) return seed.value;
    return (share * area).clamp(min, max);
  }

  @override
  void drag(double delta) {
    // Start from the width on screen, not the one last dragged to.
    if (_start == null) value = effective;
    super.drag(delta);
  }

  @override
  Future<void> save() {
    _endDrag();
    final area = this.area;
    if (area == null || area <= 0) return Future.value();
    return share.set(value / area);
  }

  @override
  Future<void> reset() {
    _endDrag();
    value = defaultValue;
    // The width shown may differ from [value] while it is unchanged.
    notifyListeners();
    final area = this.area;
    return area != null && area > 0
        ? share.set(defaultValue / area)
        : share.reset();
  }
}

/// The resizable panes beside the chat.
class PaneWidths {
  /// The space/room list beside the space bar.
  static final left = PaneWidth(preferences.leftPaneWidth);

  /// The room's side panel (banner and member list).
  static final right = PaneWidth(preferences.rightPaneWidth);

  /// Vommet issue 747: the room's side panel on its Media tab, kept as a
  /// share of the room's area so a panel widened in a full-screen window
  /// shrinks with the window instead of crowding the chat.
  static final media = SharePaneWidth(preferences.mediaPaneShare, right);

  /// Vommet issue 539: the Telegram-style chat list (without its folder
  /// strip). Only shown while that experiment is on, so always resizable.
  static final chatList = PaneWidth(preferences.chatListPaneWidth,
      min: 280, max: 640, resizableWhen: () => true);
}

/// A thin grab strip on a pane's edge: drag to resize, double-click to reset.
/// Pointing at it shows the resize cursor and lights the edge, so it can be
/// found without trying.
class PaneResizeHandle extends StatefulWidget {
  static String get paneResizeHandleTooltip =>
      Intl.message("Drag to resize, double-click to reset",
          name: "paneResizeHandleTooltip",
          desc: "Tooltip on the handle between panes that changes their width");

  const PaneResizeHandle(this.pane,
      {this.growsRight = true, this.onCollapse, super.key});

  final PaneWidth pane;

  /// Vommet issue 456: called instead of keeping the width when a drag lets
  /// go [PaneWidth.collapsePull] past the narrowest width; null, the edge
  /// just stops there.
  final VoidCallback? onCollapse;

  /// True when dragging right widens the pane (the left pane's right edge).
  final bool growsRight;

  /// The strip's width; the lit edge is drawn along its pane-side edge.
  static const width = 8.0;

  @override
  State<PaneResizeHandle> createState() => _PaneResizeHandleState();
}

class _PaneResizeHandleState extends State<PaneResizeHandle> {
  bool _hovered = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final lit = _hovered || _dragging;
    return Tooltip(
      message: PaneResizeHandle.paneResizeHandleTooltip,
      waitDuration: const Duration(seconds: 1),
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (_) => setState(() => _dragging = true),
          onHorizontalDragUpdate: (d) =>
              widget.pane.drag(widget.growsRight ? d.delta.dx : -d.delta.dx),
          onHorizontalDragEnd: (_) {
            setState(() => _dragging = false);
            final collapse = widget.onCollapse;
            if (collapse != null && widget.pane.pulledPastMin.value) {
              widget.pane.endCollapsed();
              collapse();
            } else {
              widget.pane.save();
            }
          },
          onHorizontalDragCancel: () {
            setState(() => _dragging = false);
            widget.pane.save();
          },
          onDoubleTap: widget.pane.reset,
          child: SizedBox(
            width: PaneResizeHandle.width,
            height: double.infinity,
            child: Align(
              // The pane's own edge: the left pane's right, the right pane's
              // left.
              alignment: widget.growsRight
                  ? Alignment.centerRight
                  : Alignment.centerLeft,
              child: AnimatedOpacity(
                opacity: lit ? 1 : 0,
                duration: const Duration(milliseconds: 120),
                child: SizedBox(
                  width: 2,
                  height: double.infinity,
                  child:
                      ColoredBox(color: Theme.of(context).colorScheme.primary),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Vommet issue 456: the edge of a room list collapsed to room pictures by
/// hand. Dragging it out by [pull] or more widens the list again.
class CollapsedPaneHandle extends StatefulWidget {
  static String get collapsedPaneHandleTooltip =>
      Intl.message("Drag to show room names",
          name: "collapsedPaneHandleTooltip",
          desc: "Tooltip on the edge of the room list collapsed to room "
              "pictures; dragging it out widens the list again");

  const CollapsedPaneHandle({required this.onExpand, super.key});

  final VoidCallback onExpand;

  /// How far a drag must pull the edge out to widen the list.
  static const pull = 40.0;

  @override
  State<CollapsedPaneHandle> createState() => _CollapsedPaneHandleState();
}

class _CollapsedPaneHandleState extends State<CollapsedPaneHandle> {
  bool _hovered = false;
  double? _pulled;

  @override
  Widget build(BuildContext context) {
    final lit = _hovered || _pulled != null;
    return Tooltip(
      message: CollapsedPaneHandle.collapsedPaneHandleTooltip,
      waitDuration: const Duration(seconds: 1),
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (_) => setState(() => _pulled = 0),
          onHorizontalDragUpdate: (d) => _pulled = (_pulled ?? 0) + d.delta.dx,
          onHorizontalDragEnd: (_) {
            final pulled = _pulled ?? 0;
            setState(() => _pulled = null);
            if (pulled >= CollapsedPaneHandle.pull) widget.onExpand();
          },
          onHorizontalDragCancel: () => setState(() => _pulled = null),
          child: SizedBox(
            width: PaneResizeHandle.width,
            height: double.infinity,
            child: Align(
              alignment: Alignment.centerRight,
              child: AnimatedOpacity(
                opacity: lit ? 1 : 0,
                duration: const Duration(milliseconds: 120),
                child: SizedBox(
                  width: 2,
                  height: double.infinity,
                  child:
                      ColoredBox(color: Theme.of(context).colorScheme.primary),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
