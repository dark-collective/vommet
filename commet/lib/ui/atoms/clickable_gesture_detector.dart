import 'package:flutter/material.dart';

/// A [GestureDetector] for tap targets that shows the hand cursor on desktop
/// while it has an [onTap] (Vommet issue 452).
class ClickableGestureDetector extends StatelessWidget {
  const ClickableGestureDetector(
      {super.key,
      this.onTap,
      this.onTapUp,
      this.onLongPress,
      this.onLongPressStart,
      this.onSecondaryTap,
      this.onSecondaryTapUp,
      this.behavior,
      this.child});

  final GestureTapCallback? onTap;
  final GestureTapUpCallback? onTapUp;
  final GestureLongPressCallback? onLongPress;
  final GestureLongPressStartCallback? onLongPressStart;
  final GestureTapCallback? onSecondaryTap;
  final GestureTapUpCallback? onSecondaryTapUp;
  final HitTestBehavior? behavior;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: onTap != null || onTapUp != null
          ? SystemMouseCursors.click
          : MouseCursor.defer,
      child: GestureDetector(
          onTap: onTap,
          onTapUp: onTapUp,
          onLongPress: onLongPress,
          onLongPressStart: onLongPressStart,
          onSecondaryTap: onSecondaryTap,
          onSecondaryTapUp: onSecondaryTapUp,
          behavior: behavior,
          child: child),
    );
  }
}
