import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Vommet issue 621: on iOS, dragging a finger down onto the keyboard hides
/// it, like the interactive keyboard dismiss in Messages or Telegram.
///
/// It watches touches through a global pointer route instead of a gesture
/// detector, so it never competes with the timeline's scrolling or anything
/// else: scrolling the chat works as before, and only a drag that travels
/// down and reaches the top of the keyboard (for example from the composer,
/// which sits on it) closes the keyboard. Tapping the composer opens it
/// again as usual.
class KeyboardSwipeDismiss {
  KeyboardSwipeDismiss._();

  /// How far a touch must have moved down before it can dismiss.
  static const double minTravel = 16;

  static final Set<State> _owners = {};
  static final Map<int, Offset> _starts = {};
  static bool _routed = false;

  /// Turns the gesture on while [owner] (a chat) stays mounted.
  static void attach(State owner) {
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    _owners.add(owner);
    if (_routed) return;
    GestureBinding.instance.pointerRouter.addGlobalRoute(_handle);
    _routed = true;
  }

  /// Whether a touch that went down at [start] and is now at [position]
  /// has been dragged down onto a keyboard whose top edge is at
  /// [keyboardTop] (null when no keyboard is shown).
  static bool shouldDismiss(
      {required Offset start,
      required Offset position,
      required double? keyboardTop}) {
    if (keyboardTop == null) return false;
    return position.dy - start.dy >= minTravel && position.dy >= keyboardTop;
  }

  static double? _keyboardTop() {
    final view = WidgetsBinding.instance.platformDispatcher.implicitView;
    if (view == null || view.viewInsets.bottom <= 0) return null;
    return (view.physicalSize.height - view.viewInsets.bottom) /
        view.devicePixelRatio;
  }

  static void _handle(PointerEvent event) {
    _owners.removeWhere((owner) => !owner.mounted);
    if (_owners.isEmpty) {
      GestureBinding.instance.pointerRouter.removeGlobalRoute(_handle);
      _routed = false;
      _starts.clear();
      return;
    }

    if (event.kind != PointerDeviceKind.touch) return;

    if (event is PointerDownEvent) {
      _starts[event.pointer] = event.position;
    } else if (event is PointerMoveEvent) {
      final start = _starts[event.pointer];
      if (start == null) return;
      if (shouldDismiss(
          start: start,
          position: event.position,
          keyboardTop: _keyboardTop())) {
        _starts.remove(event.pointer);
        FocusManager.instance.primaryFocus?.unfocus();
      }
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      _starts.remove(event.pointer);
    }
  }
}
