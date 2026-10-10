// Vommet (schema v11): how often the UI isolate's event loop is blocked.
// A timer asks to run every 500 ms; how late it actually runs is the time
// the loop was busy with something else (sync processing, JSON parsing,
// database work, a long build). Only runs while telemetry is enabled and the
// app is in the foreground, so it costs nothing in the background.

import 'dart:async';

import 'package:commet/telemetry/frame_stats.dart';
import 'package:commet/telemetry/telemetry.dart';
import 'package:flutter/widgets.dart';

class LoopLag {
  static const _period = Duration(milliseconds: 500);

  /// A late tick beyond this is a suspended app (or a debugger), not a
  /// busy loop, and is left out.
  static const _ignoreAboveMs = 60000;

  static final MsHistogram _lag = MsHistogram();
  static int _stalls100 = 0;
  static int _stalls1000 = 0;
  static final Stopwatch _clock = Stopwatch();
  static Timer? _timer;
  static AppLifecycleListener? _lifecycle;

  static void start() {
    if (_lifecycle != null) return;
    _lifecycle = AppLifecycleListener(
      onResume: _resume,
      onShow: _resume,
      onHide: _pause,
      onPause: _pause,
    );
    final state = WidgetsBinding.instance.lifecycleState;
    if (state == null || state == AppLifecycleState.resumed) _resume();
  }

  static void stop() {
    _lifecycle?.dispose();
    _lifecycle = null;
    _pause();
    _reset();
  }

  static void _resume() {
    if (_timer != null) return;
    _clock
      ..reset()
      ..start();
    _timer = Timer.periodic(_period, (_) => _tick());
  }

  static void _pause() {
    _timer?.cancel();
    _timer = null;
    _clock.stop();
  }

  static void _tick() {
    final lateMs = _clock.elapsedMilliseconds - _period.inMilliseconds;
    _clock
      ..reset()
      ..start();
    if (lateMs > _ignoreAboveMs) return;
    final ms = lateMs < 0 ? 0 : lateMs;
    _lag.add(ms);
    if (ms > 100) _stalls100++;
    if (ms > 1000) _stalls1000++;
  }

  static void report() {
    if (_lag.count == 0) return;
    Telemetry.record("loop_lag", {
      "samples": _lag.count.clamp(0, 1000000),
      "p95_ms": _lag.p95(),
      "worst_ms": _lag.worstMs.clamp(0, 86400000),
      "stalls_100ms": _stalls100.clamp(0, 1000000),
      "stalls_1s": _stalls1000.clamp(0, 1000000),
    });
    _reset();
  }

  static void _reset() {
    _lag.reset();
    _stalls100 = _stalls1000 = 0;
  }
}
