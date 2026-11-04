import 'dart:async';

import 'package:commet/debug/log.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
///
/// Vommet: it also stops a stuck Shift from turning taps into selections.
/// Some on-screen keyboards (Unexpected Keyboard) send key events with the
/// Shift flag set; Flutter then counts Shift as held until a later event
/// clears it, and treats every finger tap as shift+tap, which extends the
/// selection from the old cursor to the tap. A short finger tap on Android
/// therefore always just places the cursor.
class TouchSelectionNormalizer extends StatefulWidget {
  const TouchSelectionNormalizer(
      {required this.controller, required this.child, super.key});

  final TextEditingController controller;
  final Widget child;

  static bool get _platformNeedsIt =>
      defaultTargetPlatform == TargetPlatform.android;

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

  /// Collapses a selection made by a shift+tap onto the tapped end (Flutter
  /// moves the extent to the tap).
  static void collapseShiftTap(TextEditingController controller) {
    final selection = controller.selection;
    if (!selection.isValid || selection.isCollapsed) return;
    controller.selection =
        TextSelection.collapsed(offset: selection.extentOffset);
  }

  @override
  State<TouchSelectionNormalizer> createState() =>
      _TouchSelectionNormalizerState();
}

class _TouchSelectionNormalizerState extends State<TouchSelectionNormalizer> {
  Offset? _downPosition;
  Duration _downTime = Duration.zero;
  bool _shiftAtDown = false;

  static bool _isTouch(PointerEvent event) =>
      event.kind == PointerDeviceKind.touch ||
      event.kind == PointerDeviceKind.stylus;

  void _onPointerDown(PointerDownEvent event) {
    if (!TouchSelectionNormalizer._platformNeedsIt || !_isTouch(event)) {
      return;
    }
    _downPosition = event.position;
    _downTime = event.timeStamp;
    _shiftAtDown = HardwareKeyboard.instance.isShiftPressed;
  }

  void _onPointerUp(PointerUpEvent event) {
    if (!TouchSelectionNormalizer._platformNeedsIt || !_isTouch(event)) {
      return;
    }

    final down = _downPosition;
    final shiftTap = _shiftAtDown &&
        down != null &&
        (event.position - down).distance < kTouchSlop &&
        event.timeStamp - _downTime < kLongPressTimeout;
    _downPosition = null;
    _shiftAtDown = false;

    // Listeners see the pointer-up before the gesture recognizers do; wait
    // until the text field has finished the gesture.
    scheduleMicrotask(() {
      if (shiftTap && !widget.controller.selection.isCollapsed) {
        Log.w("Finger tap with Shift held (on-screen keyboard left it "
            "pressed?); placing the cursor instead of selecting");
        TouchSelectionNormalizer.collapseShiftTap(widget.controller);
      }
      TouchSelectionNormalizer.normalize(widget.controller);
    });
  }

  @override
  Widget build(BuildContext context) {
    return TapRegion(
      groupId: EditableText,
      onTapOutside: (event) => TouchSelectionNormalizer.collapseOnTapOutside(
          widget.controller, event),
      child: Listener(
        onPointerDown: _onPointerDown,
        onPointerUp: _onPointerUp,
        child: widget.child,
      ),
    );
  }
}
