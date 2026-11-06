// Vommet: which code holds the UI isolate's event loop.
//
// A tester's Linux app froze twice for ~11 s at startup while every timed
// startup step was short. ui_stall only sees a blocked loop once it is over
// and release builds have no profiler, so nothing said where the time went.
// Code now runs in named spans:
// - a zone span ([zone]) names a subsystem. Every callback scheduled from
//   inside it (timers, futures, streams, microtasks) runs in its zone, and
//   the zone times each one, so the subsystem's later work is counted too;
// - a sync span ([time]) names one synchronous section of a callback.
// Time is counted where it is spent: a span's own time leaves out the spans
// running inside it. Each span keeps its callback count, own time and worst
// single own time. LoopLag reads every span's own time on each 500 ms tick;
// on a tick late by a second or more, the time each span used since the
// previous tick is the blocked loop's breakdown (Stall_*). That also covers
// a block made of many short callbacks (a loop of awaits on finished
// futures runs as a microtask chain that never lets a timer in).
//
// Reported as timers (code identifiers with a count and a time, the schema's
// existing `timers` lists): app_ready `startup` (since launch) and
// perf_summary `timers` (since the previous summary). Only fixed span names
// and times. Cost: two clock reads per callback in a span.
//
// A block no span accounts for (Stall_none: native code on the UI thread,
// which on Linux is also GTK's main thread, the VM pausing the isolate for a
// garbage collection, or Dart code outside every span) is placed by what
// happened around it: the longest quiet gap between span callbacks in the
// blocked window is the block itself, so Stall_after_<span> names the span
// whose callback ran last before it, Stall_phase_<span> the last phase that
// had finished, and Stall_pending_<call> each platform call that was waiting
// for its reply all through it (see PlatformCalls). Other probes (the Linux
// thread probe) add their own figures ([note], [noteWorst], [sources]).

import 'dart:async';

class MainSpanStat {
  MainSpanStat(this.name);

  final String name;

  /// Callbacks (zone spans) or runs (sync spans), and their own time.
  int calls = 0;
  int ownUs = 0;
  int worstUs = 0;

  /// Runs whose own time was 100 ms or more.
  int slowCalls = 0;

  /// Blocked loop ticks this span had a share of, and that share.
  int stalls = 0;
  int stallUs = 0;

  /// Wall time from a zone span's start until its body's future finished.
  int phaseUs = -1;

  // [ownUs] at LoopLag's previous tick.
  int _tickBaseUs = 0;

  // The figures at the previous perf summary, and the worst since then.
  int _sumCalls = 0, _sumOwnUs = 0, _sumSlow = 0, _sumStalls = 0;
  int _sumStallUs = 0, _intervalWorstUs = 0;

  void _add(int own) {
    calls++;
    ownUs += own;
    if (own > worstUs) worstUs = own;
    if (own > _intervalWorstUs) _intervalWorstUs = own;
    if (own >= MainSpans.slowUs) slowCalls++;
  }
}

class _Note {
  int calls = 0, us = 0;
  int _sumCalls = 0, _sumUs = 0;
  // For [MainSpans.noteWorst]: the worst since the previous summary.
  int _intervalCalls = 0, _intervalUs = 0;
  bool worst = false;
}

class _Frame {
  _Frame(this.stat, this.startUs, this.parent);
  final MainSpanStat stat;
  final int startUs;
  final _Frame? parent;
  int childUs = 0;
}

class MainSpans {
  static final Stopwatch _stopwatch = Stopwatch()..start();
  static int Function() _now = () => _stopwatch.elapsedMicroseconds;

  /// For tests: a fake clock in microseconds (null: the real one).
  static set debugClock(int Function()? clock) =>
      _now = clock ?? () => _stopwatch.elapsedMicroseconds;

  /// A run of this much own time or more counts as slow.
  static const slowUs = 100000;

  /// A LoopLag tick this late is a blocked loop worth breaking down.
  static const stallLateMs = 1000;

  /// A span's share of a blocked tick below this is left out of it.
  static const _stallShareUs = 50000;

  /// The span names that show up: an identifier short enough that
  /// `Stall_<name>`/`Main_<name>_max` stay within the schema's 64 chars.
  static final nameRe = RegExp(r"^[A-Za-z][A-Za-z0-9_]{0,47}$");

  static final Map<String, MainSpanStat> _stats = {};
  static _Frame? _top;

  /// Spans only count while the user has opted in to diagnostics
  /// (Telemetry sets this); otherwise a span costs a flag check.
  static bool enabled = false;

  /// Whether the next [tick] has a baseline to compare with.
  static bool _armed = false;

  /// Blocked time no span accounts for: work outside every span (or
  /// waiting on something outside Dart, such as the platform thread).
  static final MainSpanStat _none = MainSpanStat("none");

  static Iterable<MainSpanStat> get stats => _stats.values;

  // Where blocks no span accounts for sat (see the top of the file).
  static int _lastEndUs = -1;
  static MainSpanStat? _lastStat;
  // LoopLag's tick ran in the current outermost callback: it is not what
  // ran before a block, so it doesn't become [_lastStat].
  static bool _tickRan = false;
  static String? _lastPhase;
  static int _gapUs = 0;
  static MainSpanStat? _gapAfter;
  static String? _gapPhase;
  static List<String>? _gapPending;

  /// The platform calls waiting for a reply (PlatformCalls), by name.
  static List<String> Function()? pendingCalls;

  /// Called on each blocked tick with how late it was, to [note] more.
  static final List<void Function(int lateMs)> stallProbes = [];

  /// Figures kept elsewhere, since launch: (name, calls, µs) each.
  static final List<Iterable<(String, int, int)> Function()> sources = [];
  static final Map<String, (int, int)> _sourceSums = {};

  static final Map<String, _Note> _notes = {};

  /// Adds [calls] and [us] to the extra timer [name] (a code name).
  static void note(String name, int calls, int us) {
    if (!nameRe64.hasMatch(name)) return;
    final n = _notes.putIfAbsent(name, () => _Note());
    n.calls += calls;
    n.us += us;
  }

  /// Keeps [value] (reported as calls) of the worst [us] seen for [name],
  /// since launch and since the previous summary.
  static void noteWorst(String name, int value, int us) {
    if (!nameRe64.hasMatch(name)) return;
    final n = _notes.putIfAbsent(name, () => _Note()..worst = true);
    if (us >= n.us) {
      n.calls = value;
      n.us = us;
    }
    if (us >= n._intervalUs) {
      n._intervalCalls = value;
      n._intervalUs = us;
    }
  }

  /// A timer name as the schema takes it (`code_name`).
  static final nameRe64 = RegExp(r"^[A-Za-z][A-Za-z0-9_]{0,63}$");

  static MainSpanStat stat(String name) {
    assert(nameRe.hasMatch(name), "bad span name $name");
    return _stats.putIfAbsent(name, () => MainSpanStat(name));
  }

  static R _enter<R>(MainSpanStat stat, R Function() body) {
    // Off, or already inside this span (a nested run of its zone, or the
    // handler of an outer zone of the same span): nothing to add.
    if (!enabled || identical(_top?.stat, stat)) return body();
    final frame = _Frame(stat, _now(), _top);
    if (frame.parent == null) _quietUntil(frame.startUs);
    _top = frame;
    try {
      return body();
    } finally {
      _top = frame.parent;
      final end = _now();
      final wall = end - frame.startUs;
      frame.parent?.childUs += wall;
      final own = wall - frame.childUs;
      stat._add(own < 0 ? 0 : own);
      if (frame.parent == null) {
        _lastEndUs = end;
        if (!_tickRan) _lastStat = stat;
        _tickRan = false;
      }
    }
  }

  // A span callback starts at [startUs] with no span running: the time since
  // the previous one ended ran no span (idle, or blocked outside them).
  static void _quietUntil(int startUs) {
    if (_lastEndUs < 0) return;
    final gap = startUs - _lastEndUs;
    if (gap <= _gapUs) return;
    _gapUs = gap;
    _gapAfter = _lastStat;
    _gapPhase = _lastPhase;
    // Calls still waiting now (this callback may be the first reply) were
    // waiting all through the gap: no Dart ran in it to send one.
    _gapPending = gap >= stallLateMs * 1000 ? pendingCalls?.call() : null;
  }

  /// Times [body], a synchronous section, as span [name]. Inside a span,
  /// the outer span's own time leaves this out.
  static R time<R>(String name, R Function() body) =>
      enabled ? _enter(stat(name), body) : body();

  /// The zone that times its callbacks as span [name], including those of
  /// zones forked inside it, except span zones (which time their own).
  static Zone zoneFor(String name, {Zone? parent}) {
    final s = stat(name);
    bool mine(Zone z) => enabled && identical(z[#vommetMainSpan], s);
    return (parent ?? Zone.current).fork(
      specification: ZoneSpecification(
        run: <R>(self, delegate, z, f) =>
            mine(z) ? _enter(s, () => delegate.run(z, f)) : delegate.run(z, f),
        runUnary: <R, T>(self, delegate, z, f, arg) => mine(z)
            ? _enter(s, () => delegate.runUnary(z, f, arg))
            : delegate.runUnary(z, f, arg),
        runBinary: <R, T1, T2>(self, delegate, z, f, a1, a2) => mine(z)
            ? _enter(s, () => delegate.runBinary(z, f, a1, a2))
            : delegate.runBinary(z, f, a1, a2),
      ),
      zoneValues: {#vommetMainSpan: s},
    );
  }

  static final Map<String, Zone> _rootZones = {};

  /// Span [name]'s zone as a child of [Zone.root] (one per name), for work
  /// the SDK runs away from its caller's zone (runInRoot).
  static Zone rootZoneFor(String name) =>
      _rootZones.putIfAbsent(name, () => zoneFor(name, parent: Zone.root));

  /// Runs [body] in span [name]'s zone (see [zoneFor]). With [phase], when
  /// [body] returns a future the wall time until it finishes is kept as the
  /// span's phase time (the first one, if the span runs more than once).
  /// Only for futures the caller awaits: the listener counts as handling
  /// an error, which would hide an unawaited future's failure.
  static R zone<R>(String name, R Function() body, {bool phase = false}) {
    final s = stat(name);
    final start = _now();
    final result = zoneFor(name).run(body);
    if (phase && enabled && result is Future && s.phaseUs < 0) {
      void done() {
        if (s.phaseUs < 0) s.phaseUs = _now() - start;
        _lastPhase = name;
      }

      result.then((_) => done(), onError: (_) => done());
    }
    return result;
  }

  /// LoopLag's tick, [lateMs] late. Each span's own time since the
  /// previous tick is its share of a blocked loop; the rest is "none".
  /// The window since the previous tick also holds up to one tick period
  /// of normal work, so the shares are scaled down to the blocked time.
  static void tick(int lateMs) {
    // The tick closes the quiet gap before it (in a span, its callback's
    // start already did), and is no span of interest itself.
    if (!enabled) return _tick(lateMs);
    if (_top != null) {
      _tickRan = true;
      return _tick(lateMs);
    }
    _quietUntil(_now());
    _tick(lateMs);
    _lastEndUs = _now();
  }

  static void _tick(int lateMs) {
    if (!_armed) {
      resume();
      return;
    }
    final blocked = lateMs >= stallLateMs;
    final blockedUs = lateMs * 1000;
    final used = <(MainSpanStat, int)>[];
    var usedUs = 0;
    for (final s in _stats.values) {
      final u = s.ownUs - s._tickBaseUs;
      s._tickBaseUs = s.ownUs;
      if (!blocked || u < _stallShareUs) continue;
      used.add((s, u));
      usedUs += u;
    }
    if (!blocked) {
      _resetGap();
      return;
    }
    var sharedUs = 0;
    for (final (s, u) in used) {
      final share = usedUs > blockedUs ? u * blockedUs ~/ usedUs : u;
      s.stalls++;
      s.stallUs += share;
      sharedUs += share;
    }
    final rest = blockedUs - sharedUs;
    if (rest >= _stallShareUs) {
      _none.stalls++;
      _none.stallUs += rest;
    }
    // The longest gap with no span callback, when it is a block of its own
    // (at most the tick's lateness: the rest of it was idle time).
    if (_gapUs >= stallLateMs * 1000) {
      final us = _gapUs < blockedUs ? _gapUs : blockedUs;
      note("Stall_after_${_gapAfter?.name ?? "start"}", 1, us);
      if (_gapPhase != null) note("Stall_phase_$_gapPhase", 1, us);
      for (final call in _gapPending ?? const <String>[]) {
        note("Stall_pending_$call", 1, us);
      }
    }
    _resetGap();
    for (final probe in stallProbes) {
      try {
        probe(lateMs);
      } catch (_) {}
    }
  }

  static void _resetGap() {
    _gapUs = 0;
    _gapAfter = null;
    _gapPhase = null;
    _gapPending = null;
  }

  /// LoopLag (re)started its timer: the next tick's window starts now.
  static void resume() {
    _armed = true;
    _resetGap();
    // Spans weren't timed while off (or not ticking): no gap from then.
    _lastEndUs = -1;
    for (final s in _stats.values) {
      s._tickBaseUs = s.ownUs;
    }
  }

  /// LoopLag stopped ticking (app in the background, or a suspended
  /// app's huge late tick): the next tick only starts a new window.
  static void pause() => _armed = false;

  static int _ms(int us) => (us ~/ 1000).clamp(0, 86400000);
  static int _count(int n) => n.clamp(0, 1000000);

  static Map<String, Object> _timer(String name, int calls, int us) =>
      {"name": name, "calls": _count(calls), "total_ms": _ms(us)};

  static List<Map<String, Object>> _build(
    Iterable<
            (
              MainSpanStat,
              int calls,
              int ownUs,
              int worstUs,
              int slow,
              int stalls,
              int stallUs
            )>
        rows, {
    required int noneStalls,
    required int noneStallUs,
    required bool phases,
    required int max,
    Iterable<(String, int, int)> extras = const [],
  }) {
    if (max <= 0) return [];
    final list = rows.where((r) => nameRe.hasMatch(r.$1.name)).toList();
    final stalls = <Map<String, Object>>[];
    for (final r in list.where((r) => r.$6 > 0).toList()
      ..sort((a, b) => b.$7.compareTo(a.$7))) {
      stalls.add(_timer("Stall_${r.$1.name}", r.$6, r.$7));
    }
    if (noneStalls > 0)
      stalls.add(_timer("Stall_none", noneStalls, noneStallUs));
    // Then what other probes noted (where a block sat, what the UI thread
    // was doing), in the order given.
    for (final (name, calls, us) in extras) {
      if (calls > 0 && nameRe64.hasMatch(name)) {
        stalls.add(_timer(name, calls, us));
      }
    }
    // Busiest spans first: own time, then (when it was slow) the worst run
    // with the count of slow runs, then how long the phase took.
    final busy = <Map<String, Object>>[];
    for (final r in list.where((r) => r.$2 > 0 && r.$3 >= 1000).toList()
      ..sort((a, b) => b.$3.compareTo(a.$3))) {
      busy.add(_timer("Main_${r.$1.name}", r.$2, r.$3));
      if (r.$4 >= slowUs) {
        busy.add(_timer("Main_${r.$1.name}_max", r.$5, r.$4));
      }
    }
    final phaseList = <Map<String, Object>>[
      if (phases)
        for (final s in list.map((r) => r.$1).where((s) => s.phaseUs >= 0))
          _timer("Phase_${s.name}", 1, s.phaseUs),
    ];
    // Stall figures take at most two thirds of the room, so the busiest
    // spans show too.
    final firstStalls = stalls.take((max * 2 + 2) ~/ 3).toList();
    return [
      ...firstStalls,
      ...busy,
      ...phaseList,
      ...stalls.skip(firstStalls.length),
    ].take(max).toList();
  }

  /// Every span since launch, for app_ready's `startup` timers: Stall_*
  /// (blocked ticks and the share of them), Main_* (callbacks, own time),
  /// Main_*_max (slow runs, the worst run) and Phase_* (zone body's wall
  /// time), at most [max] entries, most telling first.
  static List<Map<String, Object>> sinceLaunch({int max = 64}) => _build(
        _stats.values.map((s) =>
            (s, s.calls, s.ownUs, s.worstUs, s.slowCalls, s.stalls, s.stallUs)),
        noneStalls: _none.stalls,
        noneStallUs: _none.stallUs,
        phases: true,
        max: max,
        extras: [
          for (final source in sources) ..._safe(source),
          ..._sortedNotes(
              _notes.entries.map((e) => (e.key, e.value.calls, e.value.us))),
        ],
      );

  // Where blocks sat first (after/pending/phase, biggest first), then the
  // rest in their own order. Of the open-ended families (one per span or
  // call name) only the [_familyMax] biggest of each are kept.
  static const _families = [
    "Stall_after_",
    "Stall_pending_",
    "Stall_phase_",
    "Platform_slow_",
  ];
  static const _familyMax = 5;

  static List<(String, int, int)> _sortedNotes(
      Iterable<(String, int, int)> notes) {
    int rank(String n) {
      final i = _families.indexWhere(n.startsWith);
      return i < 0 ? _families.length : i;
    }

    final list = notes.where((n) => n.$2 > 0).toList()
      ..sort((a, b) {
        final r = rank(a.$1).compareTo(rank(b.$1));
        return r != 0 ? r : b.$3.compareTo(a.$3);
      });
    final kept = List.filled(_families.length, 0);
    final out = <(String, int, int)>[];
    for (final n in list) {
      final r = rank(n.$1);
      if (r < _families.length && ++kept[r] > _familyMax) continue;
      out.add(n);
    }
    return out;
  }

  static Iterable<(String, int, int)> _safe(
      Iterable<(String, int, int)> Function() source) {
    try {
      return source().toList();
    } catch (_) {
      return const [];
    }
  }

  /// The same since the previous call (for perf_summary), Phase_* left out.
  static List<Map<String, Object>> takeInterval({int max = 64}) {
    final rows = [
      for (final s in _stats.values)
        (
          s,
          s.calls - s._sumCalls,
          s.ownUs - s._sumOwnUs,
          s._intervalWorstUs,
          s.slowCalls - s._sumSlow,
          s.stalls - s._sumStalls,
          s.stallUs - s._sumStallUs,
        ),
    ];
    final read = [for (final source in sources) ..._safe(source)];
    final extras = <(String, int, int)>[
      for (final (name, calls, us) in read)
        (
          name,
          calls - (_sourceSums[name]?.$1 ?? 0),
          us - (_sourceSums[name]?.$2 ?? 0)
        ),
      ..._sortedNotes([
        for (final e in _notes.entries)
          e.value.worst
              ? (e.key, e.value._intervalCalls, e.value._intervalUs)
              : (
                  e.key,
                  e.value.calls - e.value._sumCalls,
                  e.value.us - e.value._sumUs
                ),
      ]),
    ];
    final out = _build(rows,
        noneStalls: _none.stalls - _none._sumStalls,
        noneStallUs: _none.stallUs - _none._sumStallUs,
        phases: false,
        max: max,
        extras: extras);
    for (final n in _notes.values) {
      n._sumCalls = n.calls;
      n._sumUs = n.us;
      n._intervalCalls = 0;
      n._intervalUs = 0;
    }
    for (final (name, calls, us) in read) {
      _sourceSums[name] = (calls, us);
    }
    for (final s in [..._stats.values, _none]) {
      s._sumCalls = s.calls;
      s._sumOwnUs = s.ownUs;
      s._sumSlow = s.slowCalls;
      s._sumStalls = s.stalls;
      s._sumStallUs = s.stallUs;
      s._intervalWorstUs = 0;
    }
    return out;
  }

  /// [timers] followed by [sinceLaunch], at most 64 in all.
  static List<Map<String, Object>> appendSinceLaunch(
          List<Map<String, Object>> timers) =>
      [...timers, ...sinceLaunch(max: 64 - timers.length)];

  /// [timers] followed by [takeInterval], at most 64 in all.
  static List<Map<String, Object>> appendInterval(
          List<Map<String, Object>> timers) =>
      [...timers, ...takeInterval(max: 64 - timers.length)];

  /// For tests.
  static void reset() {
    _stats.clear();
    _rootZones.clear();
    _top = null;
    _armed = false;
    _lastEndUs = -1;
    _lastStat = null;
    _tickRan = false;
    _lastPhase = null;
    _resetGap();
    _notes.clear();
    _sourceSums.clear();
    sources.clear();
    stallProbes.clear();
    pendingCalls = null;
    _none
      ..stalls = 0
      ..stallUs = 0
      .._sumStalls = 0
      .._sumStallUs = 0;
  }
}
