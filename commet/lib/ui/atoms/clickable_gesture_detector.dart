import 'package:flutter/material.dart';

/// A [GestureDetector] for tap targets that shows the hand cursor on desktop
/// while it has an [onTap] (Vommet issue 452).
class ClickableGestureDetector extends StatelessWidget {
  const ClickableGestureDetector(
      {super.key, this.onTap, this.behavior, required this.child});

  final GestureTapCallback? onTap;
  final HitTestBehavior? behavior;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
      child: GestureDetector(onTap: onTap, behavior: behavior, child: child),
    );
  }
}
