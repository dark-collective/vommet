// Vommet: frame counter (Vommet issue 350, schema v29). Counts per minute how
// many frames Flutter drew, how long their build (Dart) and raster (GPU)
// parts took, and on Linux how often GTK redrew the window (native counter in
// linux/repaint_counter.h), tagged with which top-level view was showing.
// Telling "Flutter keeps drawing frames" apart from "the window repaints
// without new frames" is the point.
//
// Runs only while telemetry is on or someone switched it on under Settings ›
// Developer › Frame counter; otherwise nothing is hooked. With telemetry on,
// one repaint_stats event per view goes out with the 15-minute perf summary.
// A minute counts for the view that was showing when it ended.

import 'dart:async';
import 'dart:collection';

import 'package:commet/config/platform_utils.dart';
import 'package:commet/telemetry/frame_stats.dart';
import 'package:commet/telemetry/telemetry.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Top-level views, by name only (never which room or space).
enum RepaintView { home, space, room, settings }

/// One finished minute (or, for [RepaintStats.current], the minute so far).
class RepaintMinute {
  final DateTime end;
  final RepaintView view;
  final int frames;
  final int buildP95Ms;
  final int rasterP95Ms;

  /// GTK window draws / frame-clock paint cycles; null off Linux.
  final int? nativeDraws;
  final int? nativePaints;

  const RepaintMinute(this.end, this.view, this.frames, this.buildP95Ms,
      this.rasterP95Ms, this.nativeDraws, this.nativePaints);
}

/// Per-view totals for one telemetry window.
class _ViewTotals {
  int minutes = 0;
  int frames = 0;
  int framesMaxMin = 0;
  int? nativeDraws;
  int? nativeDrawsMaxMin;
  int? nativePaints;
  final MsHistogram build = MsHistogram();
  final MsHistogram raster = MsHistogram();
}

class RepaintStats {
  static const _channel = MethodChannel("im.nether.vommet/repaint");

  static bool _forTelemetry = false;
  static bool _forDeveloper = false;
  static bool get running => _forTelemetry || _forDeveloper;

  /// Whether Settings › Developer › Frame counter switched it on.
  static bool get developerCounting => _forDeveloper;

  static Timer? _minuteTimer;
  static int _frames = 0;
  static final MsHistogram _build = MsHistogram();
  static final MsHistogram _raster = MsHistogram();
  static List<int>? _nativeBase;
  static bool _nativeOk = !kIsWeb && PlatformUtils.isLinux;

  static RepaintView _mainView = RepaintView.home;
  static int _settingsOpen = 0;

  /// Last 15 finished minutes, oldest first, for the developer page.
  static final ListQueue<RepaintMinute> history = ListQueue();
  static const int _historyLength = 15;
  static final ValueNotifier<int> changed = ValueNotifier(0);

  static final Map<RepaintView, _ViewTotals> _window = {};

  static RepaintView get view =>
      _settingsOpen > 0 ? RepaintView.settings : _mainView;

  /// Set by the main page on every build; a plain assignment.
  static set mainView(RepaintView v) => _mainView = v;

  static void settingsOpened() => _settingsOpen++;
  static void settingsClosed() {
    if (_settingsOpen > 0) _settingsOpen--;
  }

  static void setTelemetry(bool on) {
    _forTelemetry = on;
    if (!on) _window.clear();
    _apply();
  }

  static void setDeveloper(bool on) {
    _forDeveloper = on;
    if (!on) history.clear();
    _apply();
    changed.value++;
  }

  static void _apply() {
    if (running && _minuteTimer == null) {
      _resetMinute();
      SchedulerBinding.instance.addTimingsCallback(_onTimings);
      _minuteTimer =
          Timer.periodic(const Duration(minutes: 1), (_) => _closeMinute());
      if (_nativeOk) {
        _nativeBase = null;
        unawaited(_native("start").then((_) => _readNative()).then((v) {
          _nativeBase = v;
        }));
      }
    } else if (!running && _minuteTimer != null) {
      _minuteTimer?.cancel();
      _minuteTimer = null;
      SchedulerBinding.instance.removeTimingsCallback(_onTimings);
      if (_nativeOk) unawaited(_native("stop"));
      _resetMinute();
    }
  }

  static Future<void> _native(String method) async {
    try {
      await _channel.invokeMethod(method);
    } catch (_) {
      // No native counter (another platform, or an older runner).
      _nativeOk = false;
    }
  }

  static Future<List<int>?> _readNative() async {
    if (!_nativeOk) return null;
    try {
      final v = await _channel.invokeMethod<Object?>("read");
      if (v is List && v.length == 2) return [v[0] as int, v[1] as int];
    } catch (_) {
      _nativeOk = false;
    }
    return null;
  }

  static void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      _frames++;
      _build.add(t.buildDuration.inMilliseconds);
      _raster.add(t.rasterDuration.inMilliseconds);
    }
  }

  static void _resetMinute() {
    _frames = 0;
    _build.reset();
    _raster.reset();
  }

  /// The minute so far, without the native counts (those are read once a
  /// minute).
  static RepaintMinute current() => RepaintMinute(DateTime.now(), view, _frames,
      _build.p95orZero(), _raster.p95orZero(), null, null);

  static Future<void> _closeMinute() async {
    final v = view;
    final frames = _frames;
    final buildP95 = _build.p95orZero();
    final rasterP95 = _raster.p95orZero();
    final totals = _window.putIfAbsent(v, _ViewTotals.new);
    totals.build.addAll(_build);
    totals.raster.addAll(_raster);
    _resetMinute();

    int? draws, paints;
    final now = await _readNative();
    final base = _nativeBase;
    if (now != null && base != null) {
      draws = (now[0] - base[0]).clamp(0, 1000000);
      paints = (now[1] - base[1]).clamp(0, 1000000);
    }
    _nativeBase = now;

    totals.minutes++;
    totals.frames += frames;
    if (frames > totals.framesMaxMin) totals.framesMaxMin = frames;
    if (draws != null) {
      totals.nativeDraws = (totals.nativeDraws ?? 0) + draws;
      totals.nativePaints = (totals.nativePaints ?? 0) + (paints ?? 0);
      if (draws > (totals.nativeDrawsMaxMin ?? 0)) {
        totals.nativeDrawsMaxMin = draws;
      }
    }
    if (!_forTelemetry) _window.clear();

    if (_forDeveloper) {
      history.addLast(RepaintMinute(
          DateTime.now(), v, frames, buildP95, rasterP95, draws, paints));
      while (history.length > _historyLength) {
        history.removeFirst();
      }
      changed.value++;
    }
  }

  /// One repaint_stats event per view seen since the last report.
  static void report() {
    for (final fields in eventFields()) {
      Telemetry.record("repaint_stats", fields);
    }
    _window.clear();
  }

  static List<Map<String, Object?>> eventFields() => [
        for (final e in _window.entries)
          if (e.value.minutes > 0)
            {
              "view": e.key.name,
              "minutes": e.value.minutes.clamp(0, 1000000),
              "frames": e.value.frames.clamp(0, 1000000),
              "frames_max_min": e.value.framesMaxMin.clamp(0, 1000000),
              "build_p95_ms":
                  e.value.build.count == 0 ? null : e.value.build.p95(),
              "raster_p95_ms":
                  e.value.raster.count == 0 ? null : e.value.raster.p95(),
              "native_draws": e.value.nativeDraws?.clamp(0, 1000000),
              "native_draws_max_min":
                  e.value.nativeDrawsMaxMin?.clamp(0, 1000000),
              "native_paints": e.value.nativePaints?.clamp(0, 1000000),
            }
      ];

  static Future<void> closeMinuteForTest() => _closeMinute();

  static void addTimingsForTest(List<FrameTiming> timings) =>
      _onTimings(timings);

  static void collectForTest() => _forTelemetry = true;

  static void resetForTest() {
    _forTelemetry = _forDeveloper = false;
    _minuteTimer?.cancel();
    _minuteTimer = null;
    _settingsOpen = 0;
    _mainView = RepaintView.home;
    _nativeOk = false;
    _nativeBase = null;
    _window.clear();
    history.clear();
    _resetMinute();
  }
}

/// Marks a settings page as showing for [RepaintStats] while it's mounted.
class RepaintSettingsScope extends StatefulWidget {
  const RepaintSettingsScope({required this.child, super.key});
  final Widget child;

  @override
  State<RepaintSettingsScope> createState() => _RepaintSettingsScopeState();
}

class _RepaintSettingsScopeState extends State<RepaintSettingsScope> {
  @override
  void initState() {
    super.initState();
    RepaintStats.settingsOpened();
  }

  @override
  void dispose() {
    RepaintStats.settingsClosed();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
