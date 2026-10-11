import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Vommet: keeps a touch-made text selection in forward order (base before
/// extent) on Android.
///
/// Flutter's Android handle drag assumes base <= extent: the end handle moves
/// the extent and refuses any position at or before the base. A backward
/// selection (for example a long-press drag towards the start of the text)
/// leaves the base at the far end, so the end handle cannot move at all and
/// the start handle makes the highlight jump. Swapping the ends once the
/// finger lifts keeps the same selected text and frees both handles.
///
/// Only touch and stylus pointers trigger it, so selections extended with a
/// hardware keyboard keep their direction.
class TouchSelectionNormalizer extends StatelessWidget {
  const TouchSelectionNormalizer(
      {required this.controller, required this.child, super.key});

  final TextEditingController controller;
  final Widget child;

  static bool get _platformNeedsIt =>
      defaultTargetPlatform == TargetPlatform.android;

  void _onPointerUp(PointerUpEvent event) {
    if (!_platformNeedsIt) return;
    if (event.kind != PointerDeviceKind.touch &&
        event.kind != PointerDeviceKind.stylus) {
      return;
    }

    // Listeners see the pointer-up before the gesture recognizers do; wait
    // until the text field has finished the gesture.
    scheduleMicrotask(() => normalize(controller));
  }

  /// Swaps a backward selection into forward order, keeping the same text.
  static void normalize(TextEditingController controller) {
    final selection = controller.selection;
    if (!selection.isValid || selection.baseOffset <= selection.extentOffset) {
      return;
    }

    controller.selection = selection.copyWith(
        baseOffset: selection.extentOffset, extentOffset: selection.baseOffset);
  }

  /// Vommet: a tap outside the text field clears a selection on phones.
  /// Flutter keeps it there (only desktop unfocuses), leaving no way to get
  /// rid of the highlight except tapping into the text. Same tap-region
  /// group as the text field, so its handles and toolbar count as inside.
  static void collapseOnTapOutside(
      TextEditingController controller, PointerDownEvent event) {
    if (!_isPhone) return;
    if (event.kind != PointerDeviceKind.touch &&
        event.kind != PointerDeviceKind.stylus) {
      return;
    }
    final selection = controller.selection;
    if (!selection.isValid || selection.isCollapsed) return;
    controller.selection = TextSelection.collapsed(offset: selection.end);
  }

  static bool get _isPhone =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  Widget build(BuildContext context) {
    return TapRegion(
      groupId: EditableText,
      onTapOutside: (event) => collapseOnTapOutside(controller, event),
      child: Listener(
        onPointerUp: _onPointerUp,
        child: child,
      ),
    );
  }
}
