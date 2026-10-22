import 'dart:async';

import 'package:commet/ui/molecules/space_selector.dart';
import 'package:flutter/material.dart';

/// Vommet: a sidebar icon you can drop onto. Like Discord, dropping on it
/// moves the dragged item above or below it, and only holding over its
/// middle makes a folder: after [holdTime] it turns into a folder preview,
/// and dropping then calls [onFolder].
class RailDropTarget extends StatefulWidget {
  const RailDropTarget({
    required this.child,
    required this.size,
    required this.accepts,
    required this.onReorder,
    this.onFolder,
    this.canFolder,
    this.folderHint = "Release to make a folder",
    super.key,
  });

  final Widget child;

  /// The dragged icon's size, to find its centre.
  final double size;
  final bool Function(SidebarEntryDrag data) accepts;
  final void Function(SidebarEntryDrag data, bool below) onReorder;
  final void Function(SidebarEntryDrag data)? onFolder;
  final bool Function(SidebarEntryDrag data)? canFolder;
  final String folderHint;

  static const holdTime = Duration(milliseconds: 500);

  @override
  State<RailDropTarget> createState() => _RailDropTargetState();
}

class _RailDropTargetState extends State<RailDropTarget> {
  final link = LayerLink();
  final hint = OverlayPortalController();
  Timer? hold;
  bool armed = false;
  bool? below;

  @override
  void dispose() {
    hold?.cancel();
    super.dispose();
  }

  void reset() {
    hold?.cancel();
    hold = null;
    if (hint.isShowing) hint.hide();
    if (!mounted) return;
    setState(() {
      armed = false;
      below = null;
    });
  }

  void disarm() {
    hold?.cancel();
    hold = null;
    if (hint.isShowing) hint.hide();
    if (armed) setState(() => armed = false);
  }

  void onMove(DragTargetDetails<SidebarEntryDrag> details) {
    if (!widget.accepts(details.data)) return;

    var box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;

    // The feedback is drawn icon-sized at the grab point, so this is the
    // dragged icon's centre.
    var centre = box.globalToLocal(
        details.offset + Offset(widget.size / 2, widget.size / 2));
    var height = box.size.height;

    var isBelow = centre.dy > height / 2;
    if (isBelow != below) setState(() => below = isBelow);

    var middle = (centre.dy - height / 2).abs() < height * 0.25 &&
        widget.onFolder != null &&
        (widget.canFolder?.call(details.data) ?? true);

    if (!middle) {
      disarm();
      return;
    }

    hold ??= Timer(RailDropTarget.holdTime, () {
      if (!mounted) return;
      setState(() => armed = true);
      hint.show();
    });
  }

  @override
  Widget build(BuildContext context) {
    var colors = ColorScheme.of(context);

    return DragTarget<SidebarEntryDrag>(
      onWillAcceptWithDetails: (details) => widget.accepts(details.data),
      onMove: onMove,
      onLeave: (_) => reset(),
      onAcceptWithDetails: (details) {
        var folder = armed;
        var isBelow = below ?? false;
        reset();

        if (folder) {
          widget.onFolder?.call(details.data);
        } else {
          widget.onReorder(details.data, isBelow);
        }
      },
      builder: (context, candidates, rejected) {
        Widget child = widget.child;
        var hovering = candidates.isNotEmpty;

        if (hovering && armed) {
          child = DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.secondary, width: 2),
            ),
            child: Transform.scale(scale: 0.75, child: child),
          );
        } else if (hovering && below != null) {
          child = Stack(
            clipBehavior: Clip.none,
            children: [
              child,
              Positioned(
                left: 12,
                right: 12,
                top: below! ? null : -2,
                bottom: below! ? -2 : null,
                height: 4,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.secondary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ],
          );
        }

        return CompositedTransformTarget(
          link: link,
          child: OverlayPortal(
            controller: hint,
            overlayChildBuilder: (context) => Align(
              alignment: Alignment.topLeft,
              child: CompositedTransformFollower(
                link: link,
                targetAnchor: Alignment.centerRight,
                followerAnchor: Alignment.centerLeft,
                offset: const Offset(8, 0),
                child: IgnorePointer(
                  child: Material(
                    color: colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 5),
                      child: Text(widget.folderHint,
                          style: TextStyle(
                              color: colors.onSurface,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
              ),
            ),
            child: child,
          ),
        );
      },
    );
  }
}
