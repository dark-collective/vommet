import 'package:commet/main.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// A sidebar drag handle: long-press to drag on touch platforms (so the
/// sidebar can still scroll), immediate drag on desktop like Discord when
/// the sidebar drag experiment is on.
class SidebarDraggable<T extends Object> extends StatelessWidget {
  const SidebarDraggable({
    required this.child,
    required this.feedback,
    this.data,
    this.childWhenDragging,
    this.onDragStarted,
    this.onDragUpdate,
    this.onDragEnd,
    this.onDragCompleted,
    this.hitTestBehavior = HitTestBehavior.deferToChild,
    super.key,
  });

  final Widget child;
  final Widget feedback;
  final T? data;
  final Widget? childWhenDragging;
  final VoidCallback? onDragStarted;
  final DragUpdateCallback? onDragUpdate;
  final DragEndCallback? onDragEnd;
  final VoidCallback? onDragCompleted;
  final HitTestBehavior hitTestBehavior;

  static bool get useLongPress {
    if (!preferences.experimentSidebarDesktopDrag.value) return true;

    return switch (defaultTargetPlatform) {
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.fuchsia =>
        true,
      _ => false,
    };
  }

  @override
  Widget build(BuildContext context) {
    if (useLongPress) {
      return LongPressDraggable<T>(
        data: data,
        feedback: feedback,
        childWhenDragging: childWhenDragging,
        onDragStarted: onDragStarted,
        onDragUpdate: onDragUpdate,
        onDragEnd: onDragEnd,
        onDragCompleted: onDragCompleted,
        hitTestBehavior: hitTestBehavior,
        child: child,
      );
    }

    return Draggable<T>(
      data: data,
      feedback: feedback,
      childWhenDragging: childWhenDragging,
      onDragStarted: onDragStarted,
      onDragUpdate: onDragUpdate,
      onDragEnd: onDragEnd,
      onDragCompleted: onDragCompleted,
      hitTestBehavior: hitTestBehavior,
      child: child,
    );
  }
}
