// UI smoothness from the engine's own frame timings (no extra work per
// frame beyond a counter bump). Reported every 15 minutes with the perf
// summary, only while telemetry is enabled.

import 'package:commet/telemetry/telemetry.dart';
import 'package:flutter/scheduler.dart';

class FrameStats {
  // Upper bucket edges in ms; the last bucket is open-ended.
  static const List<int> _edges = [
    4,
    8,
    12,
    16,
    20,
    25,
    33,
    50,
    75,
    100,
    150,
    250,
    500,
    700,
    1000,
    2000
  ];
  static final List<int> _buckets = List.filled(_edges.length + 1, 0);
  static int _frames = 0;
  static int _slow = 0;
  static int _frozen = 0;
  static int _worstMs = 0;
  static bool _running = false;

  static void start() {
    if (_running) return;
    _running = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  static void stop() {
    if (!_running) return;
    _running = false;
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    _reset();
  }

  static void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      final ms = t.totalSpan.inMilliseconds;
      _frames++;
      if (ms > 16) _slow++;
      if (ms > 700) _frozen++;
      if (ms > _worstMs) _worstMs = ms;
      var i = 0;
      while (i < _edges.length && ms > _edges[i]) {
        i++;
      }
      _buckets[i]++;
    }
  }

  static int _p95() {
    final target = (_frames * 0.95).ceil();
    var seen = 0;
    for (var i = 0; i < _buckets.length; i++) {
      seen += _buckets[i];
      if (seen >= target) return i < _edges.length ? _edges[i] : _worstMs;
    }
    return _worstMs;
  }

  static void report() {
    if (_frames == 0) return;
    Telemetry.record("frame_stats", {
      "frames": _frames.clamp(0, 1000000),
      "slow_frames": _slow.clamp(0, 1000000),
      "frozen_frames": _frozen.clamp(0, 1000000),
      "worst_ms": _worstMs.clamp(0, 86400000),
      "p95_ms": _p95(),
    });
    _reset();
  }

  static void _reset() {
    _frames = _slow = _frozen = _worstMs = 0;
    _buckets.fillRange(0, _buckets.length, 0);
  }
}
