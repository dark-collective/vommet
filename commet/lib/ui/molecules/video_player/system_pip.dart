import 'package:commet/config/platform_utils.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/ui/molecules/video_player/video_player_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A video in the media viewer (or its full screen) that may go to the
/// system's picture in picture while it plays.
class SystemPipCandidate {
  SystemPipCandidate(this.controller, {this.aspectRatio});

  final VideoPlayerController controller;
  final double? aspectRatio;
}

/// Vommet issue 1081: Android's own picture-in-picture window. While a video
/// plays in the media viewer, leaving the app (home, swipe up) shrinks the
/// app into the system's floating window with only that video in it. Never
/// for paused videos or videos playing in the timeline: only the viewer adds
/// a [SystemPipCandidate]. Android only for now; iOS needs its own player
/// layer.
class SystemPip {
  static const _channel = MethodChannel("im.nether.chat/system_pip");

  /// Whether the app is in the system's picture-in-picture window.
  static final ValueNotifier<bool> active = ValueNotifier(false);

  /// Fires when the user closed the system window (not when they went back
  /// to the app), so the viewer can pause its video.
  static final ValueNotifier<int> dismissed = ValueNotifier(0);

  static bool get supported => PlatformUtils.isAndroid;

  static final List<SystemPipCandidate> _candidates = [];
  static SystemPipCandidate? _armed;
  static bool _listening = false;

  /// The candidate that goes (or went) to the system window.
  static SystemPipCandidate? get armed => _armed;

  static void add(SystemPipCandidate candidate) {
    if (!supported) return;
    _listen();
    _candidates.add(candidate);
    candidate.controller.isPlaying.addListener(_onPlayingChanged);
    update();
  }

  static void remove(SystemPipCandidate candidate) {
    if (!_candidates.remove(candidate)) return;
    candidate.controller.isPlaying.removeListener(_onPlayingChanged);
    update();
  }

  static void _onPlayingChanged() => update();

  /// The newest playing candidate, if any.
  static SystemPipCandidate? pick(List<SystemPipCandidate> candidates) {
    for (final candidate in candidates.reversed) {
      if (candidate.controller.isPlaying.value) return candidate;
    }
    return null;
  }

  /// Android takes 1:2.39 to 2.39:1; a missing or odd ratio is 16:9.
  static double aspectRatioFor(double? ratio) {
    if (ratio == null || !ratio.isFinite || ratio <= 0) return 16 / 9;
    return ratio.clamp(1 / 2.39 + 0.001, 2.39 - 0.001).toDouble();
  }

  static void update() {
    // In the system window the video may pause (its own button); keep it
    // there until the user leaves the window. A viewer that goes away
    // meanwhile stays armed until then too, which is harmless: leaving the
    // window updates again.
    if (active.value) return;
    final next = pick(_candidates);
    if (identical(next, _armed)) return;
    _armed = next;
    final ratio = aspectRatioFor(next?.aspectRatio);
    _channel.invokeMethod("setArmed", {
      "on": next != null,
      "aspectNum": (ratio * 1000).round(),
      "aspectDen": 1000,
    }).catchError((Object e) {
      Log.w("Couldn't set up the system picture in picture: $e");
    });
  }

  static void _listen() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != "changed") return;
      final args = call.arguments as Map?;
      final inPip = args?["inPip"] == true;
      active.value = inPip;
      if (!inPip) {
        if (args?["dismissed"] == true) {
          dismissed.value++;
          _armed?.controller.pause().catchError((_) {});
        }
        update();
      }
    });
  }
}
