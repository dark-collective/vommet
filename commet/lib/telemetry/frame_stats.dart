// UI smoothness from the engine's own frame timings (no extra work per
// frame beyond a counter bump). Reported every 15 minutes with the perf
// summary, only while telemetry is enabled.
//
// Vommet (schema v11): besides the whole frame, the UI thread's part (build:
// Dart layout and painting) and the GPU thread's part (raster) are kept
// separately, so a slow frame shows whether Dart work or drawing cost it.

import 'package:commet/telemetry/telemetry.dart';
import 'package:flutter/scheduler.dart';

/// Millisecond durations in fixed buckets, for a p95 without storing samples.
class MsHistogram {
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
  final List<int> _buckets = List.filled(_edges.length + 1, 0);
  int count = 0;
  int worstMs = 0;

  void add(int ms) {
    count++;
    if (ms > worstMs) worstMs = ms;
    var i = 0;
    while (i < _edges.length && ms > _edges[i]) {
      i++;
    }
    _buckets[i]++;
  }

  /// The upper edge of the bucket holding the 95th percentile.
  int p95() {
    final target = (count * 0.95).ceil();
    var seen = 0;
    for (var i = 0; i < _buckets.length; i++) {
      seen += _buckets[i];
      if (seen >= target) return i < _edges.length ? _edges[i] : worstMs;
    }
    return worstMs;
  }

  void reset() {
    count = worstMs = 0;
    _buckets.fillRange(0, _buckets.length, 0);
  }
}

class FrameStats {
  static final MsHistogram _total = MsHistogram();
  static final MsHistogram _build = MsHistogram();
  static final MsHistogram _raster = MsHistogram();
  static int _slow = 0;
  static int _frozen = 0;
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
      if (ms > 16) _slow++;
      if (ms > 700) _frozen++;
      _total.add(ms);
      _build.add(t.buildDuration.inMilliseconds);
      _raster.add(t.rasterDuration.inMilliseconds);
    }
  }

  static int _ms(int v) => v.clamp(0, 86400000);

  static void report() {
    if (_total.count == 0) return;
    Telemetry.record("frame_stats", {
      "frames": _total.count.clamp(0, 1000000),
      "slow_frames": _slow.clamp(0, 1000000),
      "frozen_frames": _frozen.clamp(0, 1000000),
      "worst_ms": _ms(_total.worstMs),
      "p95_ms": _total.p95(),
      "build_p95_ms": _build.p95(),
      "build_worst_ms": _ms(_build.worstMs),
      "raster_p95_ms": _raster.p95(),
      "raster_worst_ms": _ms(_raster.worstMs),
    });
    _reset();
  }

  static void _reset() {
    _slow = _frozen = 0;
    _total.reset();
    _build.reset();
    _raster.reset();
  }
}
