import 'dart:math' as math;

import 'package:commet/main.dart';
import 'package:commet/ui/layout/pane_widths.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class DesktopEmojiPickerGeometry {
  static const double minimum = 500;
  static const double margin = 8;
  static const double tailLength = 16;
  static const double maxDefaultWidth = 960;
  static const double maxDefaultHeight = 840;

  static Size defaultSize(Size viewport) => Size(
        (viewport.width * 0.35).clamp(minimum, maxDefaultWidth),
        (viewport.height * 0.58).clamp(minimum, maxDefaultHeight),
      );

  static Size clampSize(Size desired, Size available) {
    double clamp(double requested, double limit) =>
        requested.clamp(math.min(minimum, limit), limit);
    return Size(clamp(desired.width, available.width),
        clamp(desired.height, available.height));
  }
}

/// Vommet: the desktop picker grows with the window and resizes from its
/// top-left corner while remaining anchored above the composer (issue 1206).
class DesktopEmojiPickerContainer extends StatefulWidget {
  const DesktopEmojiPickerContainer({
    required this.anchor,
    required this.child,
    super.key,
  });

  final GlobalKey anchor;
  final Widget child;

  @override
  State<DesktopEmojiPickerContainer> createState() =>
      _DesktopEmojiPickerContainerState();
}

class _DesktopEmojiPickerContainerState
    extends State<DesktopEmojiPickerContainer> {
  Size? _draggedSize;
  Offset? _grabOffset;
  bool _hovered = false;

  Rect? get _anchorRect {
    final anchor = widget.anchor.currentContext?.findRenderObject();
    if (anchor is! RenderBox || !anchor.attached || !anchor.hasSize)
      return null;
    return anchor.localToGlobal(Offset.zero) & anchor.size;
  }

  void _startDrag(DragStartDetails details) {
    final panel = context.findRenderObject()! as RenderBox;
    _grabOffset = details.globalPosition - panel.localToGlobal(Offset.zero);
  }

  void _resize(
      DragUpdateDetails details, Rect anchor, Size viewport, Size available) {
    final grabOffset = _grabOffset;
    if (grabOffset == null) return;
    final corner = details.globalPosition - grabOffset;
    // The tooltip centers itself over the button until it reaches the right
    // margin. Invert those two positions to keep the grip under the pointer.
    final width = math.min(2 * (anchor.center.dx - corner.dx),
        viewport.width - DesktopEmojiPickerGeometry.margin - corner.dx);
    final height =
        anchor.top - DesktopEmojiPickerGeometry.tailLength - corner.dy;
    setState(() {
      _draggedSize =
          DesktopEmojiPickerGeometry.clampSize(Size(width, height), available);
    });
  }

  Future<void> _finishDrag() async {
    final size = _draggedSize;
    _grabOffset = null;
    if (size == null) return;
    await preferences.desktopEmojiPickerWidth.set(size.width);
    await preferences.desktopEmojiPickerHeight.set(size.height);
  }

  Future<void> _reset() async {
    await preferences.desktopEmojiPickerWidth.reset();
    await preferences.desktopEmojiPickerHeight.reset();
    if (mounted) setState(() => _draggedSize = null);
  }

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    final anchor = _anchorRect;
    if (anchor == null) return widget.child;

    const margin = DesktopEmojiPickerGeometry.margin;
    final available = Size(
      math.max(0, viewport.width - 2 * margin),
      math.max(0, anchor.top - DesktopEmojiPickerGeometry.tailLength - margin),
    );
    final saved = Size(preferences.desktopEmojiPickerWidth.value,
        preferences.desktopEmojiPickerHeight.value);
    final desired = _draggedSize ??
        (saved.isEmpty
            ? DesktopEmojiPickerGeometry.defaultSize(viewport)
            : saved);
    final size = DesktopEmojiPickerGeometry.clampSize(desired, available);
    final gripSize = math.min(20.0, size.shortestSide);

    return SizedBox(
      key: const ValueKey('desktop-picker-panel'),
      width: size.width,
      height: size.height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.topLeft,
            child: Tooltip(
              message: PaneResizeHandle.paneResizeHandleTooltip,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeUpLeftDownRight,
                onEnter: (_) => setState(() => _hovered = true),
                onExit: (_) => setState(() => _hovered = false),
                child: GestureDetector(
                  key: const ValueKey('desktop_picker_handle_top_left'),
                  behavior: HitTestBehavior.opaque,
                  dragStartBehavior: DragStartBehavior.down,
                  onPanStart: _startDrag,
                  onPanUpdate: (details) =>
                      _resize(details, anchor, viewport, available),
                  onPanEnd: (_) => _finishDrag(),
                  onPanCancel: _finishDrag,
                  onDoubleTap: _reset,
                  child: SizedBox.square(
                    dimension: gripSize,
                    child: Icon(Icons.drag_indicator,
                        size: math.min(16, gripSize),
                        color: _hovered
                            ? ColorScheme.of(context).primary
                            : ColorScheme.of(context).onSurfaceVariant),
                  ),
                ),
              ),
            ),
          ),
          Expanded(child: widget.child),
        ],
      ),
    );
  }
}
