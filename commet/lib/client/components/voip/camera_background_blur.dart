// Vommet: camera background blur in calls. On the web the browser blurs the
// camera with LiveKit's track processor, the one Element Call uses (built
// from scripts/vommet_blur, served from web/vommet_blur). On Android, iOS and
// macOS the flutter_webrtc fork blurs the camera track natively; on Linux and
// Windows it hands the frames to the blur in the Rust library (rust/blur).

import 'dart:async';

import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

import 'camera_background_blur_native.dart'
    if (dart.library.js_interop) 'camera_background_blur_web.dart' as impl;

class CameraBackgroundBlur {
  /// Element Call's blur radius.
  static const int blurRadius = 15;

  /// Blur switches itself off when segmenting and blurring a frame keeps
  /// taking longer than this (the camera then can't keep up at 25 fps).
  static const int slowFrameMs = 40;

  /// This build and browser (or system) can blur at all.
  static bool get supported => impl.browserSupported();

  /// The setting shows (with the experiment on).
  static bool get available =>
      supported && preferences.experimentCameraBackgroundBlur.value;

  /// The camera should be blurred when it starts.
  static bool get wanted => available && preferences.cameraBackgroundBlur.value;

  /// Blur was switched off this session because it was too slow here.
  static bool turnedOffForSpeed = false;

  static final StreamController<void> _changed =
      StreamController<void>.broadcast();

  /// Fires when blur is switched on or off, so a running call can restart
  /// its camera with or without it.
  static Stream<void> get onChanged => _changed.stream;

  static void notifyChanged() => _changed.add(null);

  /// A processor to start the camera with, or null for no blur (not wanted,
  /// or the browser can't run it).
  static Future<lk.TrackProcessor<lk.VideoProcessorOptions>?>
      createProcessor() async {
    if (!wanted) return null;
    try {
      return await impl.createBlurProcessor(
          blurRadius: blurRadius, slowFrameMs: slowFrameMs, onSlow: _tooSlow);
    } catch (e) {
      Log.w("Camera background blur unavailable: $e");
      return null;
    }
  }

  static void _tooSlow() {
    Log.w("Camera background blur too slow on this device, switching it off");
    turnedOffForSpeed = true;
    preferences.cameraBackgroundBlur.set(false);
    notifyChanged();
  }
}
