// Native side of CameraBackgroundBlur. On Android, iOS 15+ and macOS 12+ the
// flutter_webrtc fork blurs the camera track in place (vommetSetBackgroundBlur),
// so the processor has no processed track of its own and LiveKit keeps
// sending the camera track. On Linux and Windows the fork hands the camera's
// frames to the blur in the Rust library (rust/blur) and they come out on a
// new track (vommetCreateProcessedVideoTrack), which LiveKit sends instead.

import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:commet/rust/frb_generated.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart' as lk;

bool browserSupported() =>
    Platform.isAndroid ||
    Platform.isIOS ||
    Platform.isMacOS ||
    Platform.isLinux ||
    Platform.isWindows;

Future<lk.TrackProcessor<lk.VideoProcessorOptions>?> createBlurProcessor(
    {required int blurRadius,
    required int slowFrameMs,
    required void Function() onSlow}) async {
  if (!browserSupported()) return null;
  if (Platform.isLinux || Platform.isWindows) {
    return _DesktopBlurProcessor(
        blurRadius, slowFrameMs, onSlow, await _BlurLib.load());
  }
  return _NativeBlurProcessor(blurRadius, slowFrameMs, onSlow);
}

class _NativeBlurProcessor extends lk.TrackProcessor<lk.VideoProcessorOptions> {
  _NativeBlurProcessor(this.blurRadius, this.slowFrameMs, this.onSlow);

  final int blurRadius;
  final int slowFrameMs;
  final void Function() onSlow;

  String? _trackId;
  Timer? _slowCheck;

  @override
  String get name => 'vommet-background-blur';

  @override
  Future<void> init(lk.VideoProcessorOptions options) async {
    final trackId = options.track.id;
    if (trackId == null) throw StateError('camera track has no id');
    final ok = await rtc.WebRTC.invokeMethod<bool, dynamic>(
        'vommetSetBackgroundBlur', <String, dynamic>{
      'trackId': trackId,
      'enabled': true,
      'blurRadius': blurRadius,
      'slowFrameMs': slowFrameMs,
    });
    if (ok != true) {
      throw StateError('this device can\'t blur the camera');
    }
    _trackId = trackId;
    // The native side stops blurring by itself when it's too slow; check
    // now and then so the setting turns off too.
    _slowCheck = Timer.periodic(const Duration(seconds: 5), (_) async {
      final id = _trackId;
      if (id == null) return;
      final slow = await rtc.WebRTC.invokeMethod<bool, dynamic>(
          'vommetBackgroundBlurTooSlow', <String, dynamic>{'trackId': id});
      if (slow == true && _trackId == id) {
        _slowCheck?.cancel();
        onSlow();
      }
    });
  }

  @override
  Future<void> restart(lk.VideoProcessorOptions options) async {
    await destroy();
    await init(options);
  }

  @override
  Future<void> destroy() async {
    _slowCheck?.cancel();
    _slowCheck = null;
    final id = _trackId;
    _trackId = null;
    if (id == null) return;
    await rtc.WebRTC.invokeMethod<bool, dynamic>('vommetSetBackgroundBlur',
        <String, dynamic>{'trackId': id, 'enabled': false});
  }

  @override
  Future<void> onPublish(lk.Room room) async {}

  @override
  Future<void> onUnpublish() async {}

  @override
  rtc.MediaStreamTrack? get processedTrack => null;
}

/// The blur's C functions in the Rust library (rust/blur).
class _BlurLib {
  _BlurLib(ffi.DynamicLibrary lib)
      : create = lib.lookupFunction<
            ffi.Pointer<ffi.Void> Function(ffi.Uint32, ffi.Uint32),
            ffi.Pointer<ffi.Void> Function(int, int)>('vommet_blur_create'),
        destroy = lib.lookupFunction<ffi.Void Function(ffi.Pointer<ffi.Void>),
            void Function(ffi.Pointer<ffi.Void>)>('vommet_blur_destroy'),
        tooSlow = lib.lookupFunction<ffi.Bool Function(ffi.Pointer<ffi.Void>),
            bool Function(ffi.Pointer<ffi.Void>)>('vommet_blur_too_slow'),
        processFn = lib.lookupFunction<ffi.UintPtr Function(), int Function()>(
            'vommet_blur_process_fn')();

  final ffi.Pointer<ffi.Void> Function(int radius, int slowFrameMs) create;
  final void Function(ffi.Pointer<ffi.Void>) destroy;
  final bool Function(ffi.Pointer<ffi.Void>) tooSlow;
  final int processFn;

  static _BlurLib? _lib;

  static Future<_BlurLib> load() async {
    return _lib ??= _BlurLib(
        (await loadExternalLibrary(RustLib.kDefaultExternalLibraryLoaderConfig))
            .ffiDynamicLibrary);
  }
}

class _DesktopBlurProcessor
    extends lk.TrackProcessor<lk.VideoProcessorOptions> {
  _DesktopBlurProcessor(
      this.blurRadius, this.slowFrameMs, this.onSlow, this.lib);

  final int blurRadius;
  final int slowFrameMs;
  final void Function() onSlow;
  final _BlurLib lib;

  ffi.Pointer<ffi.Void>? _blur;
  rtc.MediaStreamTrack? _processed;
  Timer? _slowCheck;

  @override
  String get name => 'vommet-background-blur';

  @override
  Future<void> init(lk.VideoProcessorOptions options) async {
    final blur = lib.create(blurRadius, slowFrameMs);
    if (blur == ffi.nullptr) {
      throw StateError('the background blur model didn\'t load');
    }
    final rtc.MediaStreamTrack processed;
    try {
      processed = await rtc.vommetCreateProcessedVideoTrack(
          options.track, lib.processFn, blur.address);
    } catch (_) {
      lib.destroy(blur);
      rethrow;
    }
    _blur = blur;
    _processed = processed;
    // The blur stops by itself when it's too slow; check now and then so
    // the setting turns off too.
    _slowCheck = Timer.periodic(const Duration(seconds: 5), (_) {
      final b = _blur;
      if (b != null && lib.tooSlow(b)) {
        _slowCheck?.cancel();
        onSlow();
      }
    });
  }

  @override
  Future<void> restart(lk.VideoProcessorOptions options) async {
    await destroy();
    await init(options);
  }

  @override
  Future<void> destroy() async {
    _slowCheck?.cancel();
    _slowCheck = null;
    final processed = _processed;
    final blur = _blur;
    _processed = null;
    _blur = null;
    // Disposing the processed track waits for the frame in flight, after
    // which the blur is no longer used and can be freed. If that fails the
    // blur is left alone rather than freed under a running frame.
    if (processed != null) await processed.stop();
    if (blur != null) lib.destroy(blur);
  }

  @override
  Future<void> onPublish(lk.Room room) async {}

  @override
  Future<void> onUnpublish() async {}

  @override
  rtc.MediaStreamTrack? get processedTrack => _processed;
}
