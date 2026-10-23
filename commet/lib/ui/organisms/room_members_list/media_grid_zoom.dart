import 'package:commet/main.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Vommet issue 622: the Media tab's thumbnail size, which Ctrl + mouse
/// wheel (or a pinch on a touch screen) steps through. Remembered on this
/// device for every room ([VommetPreferences.mediaGridThumbnailSize]).
class MediaGridZoom {
  /// The sizes a step moves between, in logical pixels (the grid's widest
  /// thumbnail; the grid fits as many per row as that allows).
  static const sizes = <double>[64, 80, 96, 110, 140, 180, 230, 280, 320];

  static double get size => preferences.mediaGridThumbnailSize.value;

  /// The size one step bigger ([direction] 1) or smaller (-1) than
  /// [current], which need not be one of [sizes].
  static double step(double current, int direction) {
    var nearest = 0;
    for (var i = 1; i < sizes.length; i++) {
      if ((sizes[i] - current).abs() < (sizes[nearest] - current).abs()) {
        nearest = i;
      }
    }
    final index = (nearest + direction).clamp(0, sizes.length - 1);
    return sizes[index];
  }

  static void stepBy(int direction) {
    final next = step(size, direction);
    if (next != size) preferences.mediaGridThumbnailSize.set(next);
  }
}

/// Lets a scroll view ignore the mouse wheel while Ctrl is held, so
/// [MediaGridZoomDetector] above it gets the wheel instead.
class NoWheelWhileCtrlScrollPhysics extends ScrollPhysics {
  const NoWheelWhileCtrlScrollPhysics({super.parent});

  @override
  NoWheelWhileCtrlScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      NoWheelWhileCtrlScrollPhysics(parent: buildParent(ancestor));

  @override
  bool shouldAcceptUserOffset(ScrollMetrics position) =>
      !HardwareKeyboard.instance.isControlPressed &&
      super.shouldAcceptUserOffset(position);
}

/// Resizes the Media tab's thumbnails: Ctrl + wheel up makes them bigger,
/// Ctrl + wheel down smaller; on a touch screen two fingers pinching apart
/// or together do the same. The scroll view below must use
/// [NoWheelWhileCtrlScrollPhysics].
class MediaGridZoomDetector extends StatefulWidget {
  const MediaGridZoomDetector({required this.child, super.key});
  final Widget child;

  @override
  State<MediaGridZoomDetector> createState() => _MediaGridZoomDetectorState();
}

class _MediaGridZoomDetectorState extends State<MediaGridZoomDetector> {
  /// Wheel distance since the last step; a mouse notch is one step, a
  /// trackpad's many small deltas add up to one.
  double _wheel = 0;
  static const _wheelPerStep = 50.0;

  final Map<int, Offset> _touches = {};
  double? _pinchStart;

  /// How far apart the fingers must move (as a ratio) for one step.
  static const _pinchPerStep = 1.25;

  void _onSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent ||
        !HardwareKeyboard.instance.isControlPressed) {
      return;
    }
    GestureBinding.instance.pointerSignalResolver.register(event, (event) {
      final dy = (event as PointerScrollEvent).scrollDelta.dy;
      if (dy == 0) return;
      // A change of direction starts counting again.
      if (_wheel.sign != dy.sign) _wheel = 0;
      _wheel += dy;
      if (_wheel.abs() >= _wheelPerStep) {
        // Wheel up (negative) = bigger.
        MediaGridZoom.stepBy(_wheel < 0 ? 1 : -1);
        _wheel = 0;
      }
    });
  }

  double? get _spread {
    if (_touches.length != 2) return null;
    final points = _touches.values.toList();
    return (points[0] - points[1]).distance;
  }

  void _onDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.touch) return;
    _touches[event.pointer] = event.position;
    _pinchStart = _spread;
  }

  void _onMove(PointerMoveEvent event) {
    if (!_touches.containsKey(event.pointer)) return;
    _touches[event.pointer] = event.position;
    final start = _pinchStart, spread = _spread;
    if (start == null || spread == null || start <= 0) return;
    final ratio = spread / start;
    if (ratio >= _pinchPerStep || ratio <= 1 / _pinchPerStep) {
      MediaGridZoom.stepBy(ratio > 1 ? 1 : -1);
      _pinchStart = spread;
    }
  }

  void _onUp(PointerEvent event) {
    _touches.remove(event.pointer);
    _pinchStart = _spread;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: _onSignal,
      onPointerDown: _onDown,
      onPointerMove: _onMove,
      onPointerUp: _onUp,
      onPointerCancel: _onUp,
      child: widget.child,
    );
  }
}
