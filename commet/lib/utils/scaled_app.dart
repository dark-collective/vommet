//Borrowed with love, from https://github.com/LastMonopoly/scaled_app
import 'dart:async' show scheduleMicrotask, Timer;
import 'dart:collection' show Queue;
import 'dart:ui' show PointerDataPacket;
import 'package:flutter/rendering.dart' show RenderView, ViewConfiguration;
import 'package:flutter/gestures.dart' show FlutterView, PointerEventConverter;
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart' show BinaryMessenger;
import 'package:commet/telemetry/platform_calls.dart';

/// The size of the screen is in logical pixels.
///
/// Scale of 1 means original size.
///
typedef ScaleFactorCallback = double Function(Size deviceSize);

/// Replace [runApp] with [runAppScaled] in `main()`.
///
/// Scaling will be applied based on [scaleFactor] callback.
///
void runAppScaled(Widget app, {ScaleFactorCallback? scaleFactor}) {
  WidgetsBinding binding = ScaledWidgetsFlutterBinding.ensureInitialized(
    scaleFactor: scaleFactor,
  );
  Timer.run(() {
    binding.attachRootWidget(binding.wrapWithDefaultView(app));
  });
  binding.scheduleWarmUpFrame();
}

/// Adapted from [WidgetsFlutterBinding]
///
class ScaledWidgetsFlutterBinding extends WidgetsFlutterBinding {
  /// Calculate scale factor from device size.
  ScaleFactorCallback? _scaleFactor;

  ScaledWidgetsFlutterBinding._({ScaleFactorCallback? scaleFactor})
      : _scaleFactor = scaleFactor;

  ScaleFactorCallback get scaleFactor => _scaleFactor ?? (_) => 1.0;

  /// Update scaleFactor callback, then rebuild layout
  set scaleFactor(ScaleFactorCallback? callback) {
    _scaleFactor = callback;
    handleMetricsChanged();
  }

  double get scale {
    final FlutterView? view = platformDispatcher.implicitView;
    if (view == null) return 1;
    return scaleFor(view);
  }

  /// Vommet: the scale of [view] (the main window, or another window such
  /// as a stream's pop-out, stream_popout_window.dart).
  double scaleFor(FlutterView view) =>
      scaleFactor(view.physicalSize / view.devicePixelRatio);

  /// The main window's scaled device pixel ratio.
  double devicePixelRatioScaled = 0;

  /// Vommet: every window's scaled device pixel ratio, by view id, for the
  /// pointer events of each window (see [_handlePointerDataPacket]).
  final Map<int, double> _devicePixelRatiosScaled = {};

  bool get isScaling => scale != 1.0;

  static ScaledWidgetsFlutterBinding? _binding;

  /// Scaling will be applied based on [scaleFactor] callback.
  ///
  static WidgetsBinding ensureInitialized({ScaleFactorCallback? scaleFactor}) {
    _binding ??= ScaledWidgetsFlutterBinding._(scaleFactor: scaleFactor);
    return _binding!;
  }

  static ScaledWidgetsFlutterBinding get instance => _binding!;

  /// Vommet: platform calls go through a messenger that knows which are
  /// waiting for a reply (diagnostics only, see PlatformCalls).
  @override
  BinaryMessenger createBinaryMessenger() {
    PlatformCalls.install();
    return TimedBinaryMessenger(super.createBinaryMessenger());
  }

  /// Vommet: null when another binding is in use (the integration tests'),
  /// so startGui() can run under test.
  static ScaledWidgetsFlutterBinding? get maybeInstance => _binding;
  @override
  ViewConfiguration createViewConfigurationFor(RenderView renderView) {
    // Vommet: the render view's own window, not always the main one: a
    // second window (a stream's pop-out) would get the main window's size.
    final FlutterView view = renderView.flutterView;
    final devicePixelRatio = view.devicePixelRatio;

    final BoxConstraints physicalConstraints =
        BoxConstraints.fromViewConstraints(view.physicalConstraints);

    final physicalSize = view.physicalSize;

    if (physicalSize.isEmpty) {
      return super.createViewConfigurationFor(renderView);
    } else {
      final scaled = devicePixelRatio * scaleFor(view);
      _devicePixelRatiosScaled[view.viewId] = scaled;
      if (view == platformDispatcher.implicitView) {
        devicePixelRatioScaled = scaled;
      }
      return ViewConfiguration(
        physicalConstraints: physicalConstraints,
        logicalConstraints: physicalConstraints / scaled,
        devicePixelRatio: scaled,
      );
    }
  }
  // @override
  // SingletonFlutterWindow get window => super.window;

  /// Adapted from [GestureBinding.initInstances]
  @override
  void initInstances() {
    super.initInstances();
    platformDispatcher.onPointerDataPacket = _handlePointerDataPacket;
  }

  @override
  void unlocked() {
    super.unlocked();
    _flushPointerEventQueue();
  }

  final Queue<PointerEvent> _pendingPointerEvents = Queue<PointerEvent>();

  /// When we scale UI using [ViewConfiguration], [ui.window] stays the same.
  ///
  /// [GestureBinding] uses [platformDispatcher.implicitView.devicePixelRatio] for calculations,
  /// so we override corresponding methods.
  ///
  void _handlePointerDataPacket(PointerDataPacket packet) {
    // We convert pointer data to logical pixels so that e.g. the touch slop can be
    // defined in a device-independent manner.
    try {
      _pendingPointerEvents.addAll(PointerEventConverter.expand(
        packet.data,
        (viewId) {
          return _devicePixelRatiosScaled[viewId] ??
              platformDispatcher.view(id: viewId)?.devicePixelRatio ??
              devicePixelRatioScaled;
        },
      ));
      if (!locked) {
        _flushPointerEventQueue();
      }
    } catch (error, stack) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'gestures library',
        context:
            ErrorDescription('while handling a scaled pointer data packet'),
      ));
    }
  }

  /// Dispatch a [PointerCancelEvent] for the given pointer soon.
  ///
  /// The pointer event will be dispatched before the next pointer event and
  /// before the end of the microtask but not within this function call.
  @override
  void cancelPointer(int pointer) {
    if (_pendingPointerEvents.isEmpty && !locked) {
      scheduleMicrotask(_flushPointerEventQueue);
    }
    _pendingPointerEvents.addFirst(PointerCancelEvent(pointer: pointer));
  }

  void _flushPointerEventQueue() {
    assert(!locked);

    while (_pendingPointerEvents.isNotEmpty) {
      handlePointerEvent(_pendingPointerEvents.removeFirst());
    }
  }
}

extension ScaledMediaQueryData on MediaQueryData {
  /// Scale MediaQueryData accordingly,
  /// so that widgets using [MediaQueryData.size],
  /// [MediaQueryData.devicePixelRatio], [MediaQueryData.viewInsets],
  /// [MediaQueryData.viewPadding], [MediaQueryData.padding]
  /// can be laid out correctly.
  ///
  /// e.g. keyboard, appBar, navigationBar.
  ///
  MediaQueryData scale() {
    final scale = (ScaledWidgetsFlutterBinding._binding?.scale ?? 1);
    return copyWith(
      size: size / scale,
      devicePixelRatio: devicePixelRatio * scale,
      viewInsets: viewInsets / scale,
      viewPadding: viewPadding / scale,
      padding: padding / scale,
    );
  }
}
