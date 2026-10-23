import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Vommet: swipe left or right to change tabs, as in Discord's channel panel.
///
/// A swipe toward a tab that doesn't exist (right on the first tab, left on
/// the last) is not claimed, so it falls through to whatever is behind: on
/// phones the side panel, which then closes. Touch, stylus and trackpad only;
/// a mouse drag keeps selecting text.
class TabSwipeDetector extends StatelessWidget {
  const TabSwipeDetector(
      {required this.child,
      required this.canSwipe,
      required this.onSwipe,
      this.startsHere,
      super.key});

  final Widget child;

  /// Whether there is a tab in [direction]: 1 for the next (swipe left), -1
  /// for the previous (swipe right).
  final bool Function(int direction) canSwipe;
  final void Function(int direction) onSwipe;

  /// Whether a touch starting at this global position may change tabs; one
  /// that doesn't (the header, the tab strip, the panel's edge) always goes
  /// to the panel behind. Null for anywhere.
  final bool Function(Offset globalPosition)? startsHere;

  /// A swipe this far, or this fast, changes the tab.
  static const double minDistance = 48;
  static const double minVelocity = 300;

  /// The tab direction for a finished swipe, or 0 for none.
  static int directionOf(double dx, double velocity) {
    if (velocity.abs() >= minVelocity) return velocity < 0 ? 1 : -1;
    if (dx.abs() >= minDistance) return dx < 0 ? 1 : -1;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    double dx = 0;
    return RawGestureDetector(
      gestures: {
        _TabSwipeRecognizer:
            GestureRecognizerFactoryWithHandlers<_TabSwipeRecognizer>(
          () => _TabSwipeRecognizer(canSwipe),
          (recognizer) {
            recognizer
              ..canSwipe = canSwipe
              ..startsHere = startsHere
              ..onStart = (_) {
                dx = 0;
              }
              ..onUpdate = (details) {
                dx += details.delta.dx;
              }
              ..onEnd = (details) {
                final direction =
                    directionOf(dx, details.velocity.pixelsPerSecond.dx);
                if (direction != 0 && canSwipe(direction)) onSwipe(direction);
              };
          },
        ),
      },
      child: child,
    );
  }
}

class _TabSwipeRecognizer extends HorizontalDragGestureRecognizer {
  _TabSwipeRecognizer(this.canSwipe)
      : super(supportedDevices: {
          PointerDeviceKind.touch,
          PointerDeviceKind.stylus,
          PointerDeviceKind.trackpad,
        });

  bool Function(int direction) canSwipe;
  bool Function(Offset globalPosition)? startsHere;
  double _moved = 0;

  @override
  bool isPointerAllowed(PointerEvent event) =>
      super.isPointerAllowed(event) &&
      (startsHere?.call(event.position) ?? true);

  @override
  bool isPointerPanZoomAllowed(PointerPanZoomStartEvent event) =>
      super.isPointerPanZoomAllowed(event) &&
      (startsHere?.call(event.position) ?? true);

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _moved = 0;
    super.addAllowedPointer(event);
  }

  @override
  void addAllowedPointerPanZoom(PointerPanZoomStartEvent event) {
    _moved = 0;
    super.addAllowedPointerPanZoom(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent) _moved += event.delta.dx;
    if (event is PointerPanZoomUpdateEvent) _moved = event.pan.dx;
    super.handleEvent(event);
  }

  // Claim the drag only toward a tab that exists; otherwise let the panel
  // behind have it.
  @override
  bool hasSufficientGlobalDistanceToAccept(
      PointerDeviceKind pointerDeviceKind, double? deviceTouchSlop) {
    if (!super.hasSufficientGlobalDistanceToAccept(
        pointerDeviceKind, deviceTouchSlop)) {
      return false;
    }
    return canSwipe(_moved < 0 ? 1 : -1);
  }
}
