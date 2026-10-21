// Vommet (schema v20): freezes, reported as they happen. A tester's window
// froze after leaving a call and was force-quit before the 15-minute
// loop_lag/frame_stats summary went out, so nothing showed. A `ui_stall`
// event goes out (and is flushed at once) when one of these passes
// [threshold]:
// - loop: the UI isolate's event loop was blocked. Seen by LoopLag's late
//   tick, so reported when it ends.
// - platform: the platform thread has not answered a no-op message. On
//   desktop Linux that is the GTK main thread, which also delivers input and
//   presents frames, so the window looks frozen while Dart keeps running.
//   Reported while it is still stuck, and again when it answers.
// - frame: a frame was requested but none started while the app is focused
//   (the raster side is stuck). Reported while stuck, and again when a frame
//   starts.
// The checks ride LoopLag's 500 ms tick, so they only run while telemetry is
// enabled and the app is in the foreground. The platform probe is a few
// bytes every 2 s; the frame check is a counter bump per frame.

import 'package:commet/telemetry/telemetry.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class UiStall {
  static const threshold = Duration(seconds: 5);
  static const _pingEvery = Duration(seconds: 2);

  /// At most this many `ui_stall` events per session.
  static const _maxEvents = 20;

  // An unknown method on the platform channel: every embedder answers it
  // with "not implemented" from its platform thread, and does nothing else.
  static final ByteData _ping = const JSONMethodCodec()
      .encodeMethodCall(const MethodCall("Vommet.stallProbe"));

  static final Stopwatch _clock = Stopwatch()..start();
  static int _events = 0;

  static int? _pingSentMs;
  static int _lastPingMs = -1000000;
  static bool _pingReported = false;

  static bool _frameCounterAdded = false;
  static int _frames = 0;
  static int _framesSeen = 0;
  static int? _frameWaitSinceMs;
  static bool _frameReported = false;

  static int _activeCalls = 0;
  static int? _lastCallEndMs;
  static int? _lastCallParticipants;

  static void callStarted() => _activeCalls++;

  static void callEnded(int maxParticipants) {
    if (_activeCalls > 0) _activeCalls--;
    _lastCallEndMs = _clock.elapsedMilliseconds;
    _lastCallParticipants = maxParticipants;
  }

  /// Called by LoopLag when its timer starts.
  static void start() {
    if (_frameCounterAdded) return;
    _frameCounterAdded = true;
    // Persistent frame callbacks can't be removed; this one only counts.
    SchedulerBinding.instance.addPersistentFrameCallback((_) => _frames++);
  }

  /// Called by LoopLag when its timer stops (background or telemetry off).
  static void pause() {
    _frameWaitSinceMs = null;
    _frameReported = false;
    _pingSentMs = null;
    _pingReported = false;
  }

  /// LoopLag's late tick, in ms.
  static void loopLate(int lateMs) {
    if (lateMs < threshold.inMilliseconds) return;
    _record("loop", lateMs, ongoing: false);
  }

  /// Every LoopLag tick (500 ms), with how late it ran.
  static void tick(int lateMs) {
    final now = _clock.elapsedMilliseconds;
    if (lateMs >= 1000) {
      // The loop itself was blocked, which also holds up the probe's answer
      // and frames: restart their clocks rather than count it twice.
      if (_pingSentMs != null && !_pingReported) _pingSentMs = now;
      if (!_frameReported) _frameWaitSinceMs = null;
    }
    _checkPlatform(now);
    _checkFrames(now);
  }

  static void _checkPlatform(int now) {
    final sent = _pingSentMs;
    if (sent != null) {
      if (!_pingReported && now - sent >= threshold.inMilliseconds) {
        _pingReported = true;
        _record("platform", now - sent, ongoing: true);
      }
      return;
    }
    if (now - _lastPingMs < _pingEvery.inMilliseconds) return;
    _lastPingMs = now;
    _pingSentMs = now;
    final reply = ServicesBinding.instance.defaultBinaryMessenger
        .send("flutter/platform", _ping);
    if (reply == null) {
      _pingSentMs = null;
      return;
    }
    reply.then((_) => _pingAnswered(), onError: (_) => _pingAnswered());
  }

  static void _pingAnswered() {
    final sent = _pingSentMs;
    _pingSentMs = null;
    if (sent == null) return;
    if (_pingReported) {
      _pingReported = false;
      _record("platform", _clock.elapsedMilliseconds - sent, ongoing: false);
    }
  }

  static void _checkFrames(int now) {
    final focused =
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    final progressed = _frames != _framesSeen;
    _framesSeen = _frames;
    final waiting =
        focused && SchedulerBinding.instance.hasScheduledFrame && !progressed;
    if (!waiting) {
      final since = _frameWaitSinceMs;
      if (since != null && _frameReported && progressed) {
        _record("frame", now - since, ongoing: false);
      }
      _frameWaitSinceMs = null;
      _frameReported = false;
      return;
    }
    final since = _frameWaitSinceMs ??= now;
    if (!_frameReported && now - since >= threshold.inMilliseconds) {
      _frameReported = true;
      _record("frame", now - since, ongoing: true);
    }
  }

  static void _record(String kind, int ms, {required bool ongoing}) {
    if (_events >= _maxEvents) return;
    _events++;
    final now = _clock.elapsedMilliseconds;
    final callEnd = _lastCallEndMs;
    Telemetry.record("ui_stall", {
      "kind": kind,
      "ms": ms.clamp(0, 86400000),
      "ongoing": ongoing,
      "foreground":
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
      "in_call": _activeCalls > 0,
      if (callEnd != null)
        "since_call_end_s": ((now - callEnd) ~/ 1000).clamp(0, 2592000),
      if (_lastCallParticipants != null)
        "call_participants": _lastCallParticipants!.clamp(0, 1000000),
    });
    Telemetry.flush();
  }
}
