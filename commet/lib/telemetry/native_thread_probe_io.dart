// Vommet: what the UI thread was doing while the Dart event loop was blocked
// (Linux only, diagnostics on).
//
// A blocked loop that no span accounts for (Stall_none) ran no Dart code:
// native code held the UI thread (on Linux that is GTK's main thread), or the
// VM had paused the isolate, for instance to collect garbage. A small helper
// isolate tells these apart from outside. LoopLag's 500 ms tick writes the
// time of each beat to memory both isolates share; once a beat is 100 ms
// overdue, the helper samples the UI thread every 100 ms from /proc (its
// state, and the system call it is waiting in: futex, poll, read on a
// socket…) and, a second in, reads every thread's CPU time, again when the
// loop runs. Two beats 1.5 s or more apart (a tick a second late, as
// MainSpans counts it) make a block: Stall_probe_blocks. If the helper was
// held up in one too, the VM had paused the whole isolate group (a garbage
// collection stops every isolate) or the process was not running:
// Stall_probe_paused. A blocked tick also notes the app's memory (RSS) and
// the system's available memory at the worst block.
//
// Reported as extra Stall_* timers in app_ready `startup` and perf_summary
// `timers` (see MainSpans.sources): sample counts and times only, with fixed
// names; /proc paths, thread names and file names are never reported (a
// thread is only "UI", "Dart worker", "raster" or "other", a file only
// socket/pipe/file/gpu).

import 'dart:async';
import 'dart:developer';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:commet/telemetry/main_spans.dart';
import 'package:ffi/ffi.dart';

// Shared memory slots (Int64 each).
const _hb = 0; // the last beat (Timeline.now, µs); 0 = not ticking
const _blocks =
    1; // blocks: heartbeat still for 1.5 s or more (a tick 1 s late)
const _blockMs = 2; // how late those ticks were
const _cpuBlocks = 3; // blocks with CPU figures (the helper ran in them)
const _cpuUi = 4; // CPU ms in those blocks: the UI thread
const _cpuWorkers = 5; // … Dart's worker threads (GC, other isolates)
const _cpuRaster = 6; // … the raster thread
const _cpuOther = 7; // … every other thread
const _workersBusy = 8; // Dart workers at ≥ half a CPU, summed over blocks
const _majorFaults = 9; // major page faults in those blocks (disk or swap)
const _pausedBlocks = 10; // blocks during which the helper was held up too
const _pausedMs = 11; // how long it was held up in them
const _classBase = 12; // UI thread samples by class (100 ms each)
const _slots = 48;

/// The heartbeat's period (LoopLag's tick).
const _beatMs = 500;

const _samplePeriodMs = 100;

/// What the UI thread was doing in a sample.
const probeClasses = [
  "run", // on a CPU (Dart, VM or native code)
  "disk", // uninterruptible sleep (disk, or memory being paged in)
  "futex", // waiting on a lock or condition (another thread)
  "poll", // waiting for file or socket events (a nested main loop…)
  "sleep",
  "wait_child", // waiting for a child process
  "read_socket",
  "read_pipe",
  "read_file",
  "read_other",
  "write_socket",
  "write_pipe",
  "write_file",
  "write_other",
  "ioctl_gpu",
  "ioctl_other",
  "fsync",
  "open",
  "mem", // mmap, munmap, madvise, brk
  "lock", // flock, fcntl
  "other",
];

class NativeThreadProbe {
  static Pointer<Int64>? _mem;
  static bool _tried = false;

  /// LoopLag (re)started ticking: start the helper the first time.
  static void resume() {
    if (!_tried) _start();
    _mem?[_hb] = Timeline.now;
  }

  /// One LoopLag tick: the event loop ran.
  static void beat() {
    _mem?[_hb] = Timeline.now;
  }

  /// LoopLag stopped ticking: a still heartbeat is no block now.
  static void pause() {
    _mem?[_hb] = 0;
  }

  static void _start() {
    _tried = true;
    if (!Platform.isLinux) return;
    try {
      final uiTid = _currentThreadId();
      if (uiTid != pid) MainSpans.noteWorst("Ui_thread_separate", 1, 0);
      final memTotal = _memInfoMb("MemTotal");
      if (memTotal != null) MainSpans.noteWorst("Mem_total_mb", memTotal, 0);
      final mem = calloc<Int64>(_slots);
      _mem = mem;
      MainSpans.sources.add(_figures);
      MainSpans.stallProbes.add(_onStall);
      // Never freed: the helper may still read it, and it is 384 bytes.
      unawaited(Isolate.spawn(_helperMain, [mem.address, uiTid],
              debugName: "Vommet thread probe", errorsAreFatal: false)
          .then((_) {}, onError: (_) {}));
    } catch (_) {
      _mem = null;
    }
  }

  // The UI isolate's thread id: /proc/thread-self is "<pid>/task/<tid>".
  static int _currentThreadId() {
    try {
      final target = Link("/proc/thread-self").targetSync();
      final tid = int.tryParse(target.split("/").last);
      if (tid != null) return tid;
    } catch (_) {}
    return pid;
  }

  static int? _memInfoMb(String key) {
    try {
      for (final line in File("/proc/meminfo").readAsLinesSync()) {
        if (line.startsWith("$key:")) {
          final kb = int.tryParse(line.split(RegExp(r"\s+"))[1]);
          return kb == null ? null : kb ~/ 1024;
        }
      }
    } catch (_) {}
    return null;
  }

  // A blocked tick, on the UI isolate: memory at the worst block.
  static void _onStall(int lateMs) {
    final us = lateMs * 1000;
    MainSpans.noteWorst("Stall_worst_rss_mb", ProcessInfo.currentRss >> 20, us);
    final avail = _memInfoMb("MemAvailable");
    if (avail != null)
      MainSpans.noteWorst("Stall_worst_mem_avail_mb", avail, us);
  }

  static Iterable<(String, int, int)> _figures() {
    final mem = _mem;
    if (mem == null) return const [];
    final blocks = mem[_blocks];
    if (blocks <= 0) return const [];
    final blockUs = mem[_blockMs] * 1000;
    final out = <(String, int, int)>[
      ("Stall_probe_blocks", blocks, blockUs),
      ("Stall_probe_paused", mem[_pausedBlocks], mem[_pausedMs] * 1000),
      ("Stall_cpu_ui_thread", mem[_cpuBlocks], mem[_cpuUi] * 1000),
      ("Stall_cpu_dart_workers", mem[_cpuBlocks], mem[_cpuWorkers] * 1000),
      ("Stall_cpu_raster", mem[_cpuBlocks], mem[_cpuRaster] * 1000),
      ("Stall_cpu_other_threads", mem[_cpuBlocks], mem[_cpuOther] * 1000),
      ("Stall_dart_workers_busy", mem[_workersBusy], blockUs),
      ("Stall_major_faults", mem[_majorFaults], blockUs),
    ];
    final classes = <(String, int, int)>[
      for (var i = 0; i < probeClasses.length; i++)
        if (mem[_classBase + i] > 0)
          (
            "Stall_thread_${probeClasses[i]}",
            mem[_classBase + i],
            mem[_classBase + i] * _samplePeriodMs * 1000
          ),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    return [...classes, ...out];
  }
}

// The helper isolate.

void _helperMain(List<int> args) {
  _Helper(Pointer<Int64>.fromAddress(args[0]), args[1]).schedule();
}

class _ThreadCpu {
  _ThreadCpu(this.atMs, this.ticks, this.uiTicks, this.majorFaults);
  final int atMs;
  final Map<int, (String, int)> ticks; // tid -> (kind, utime + stime)
  final int uiTicks;
  final int majorFaults;
}

class _Helper {
  _Helper(this.mem, this.uiTid)
      : _syscalls = probeSyscalls(Abi.current()),
        _clockTicksPerS = 100;

  final Pointer<Int64> mem;
  final int uiTid;
  final Map<int, String> _syscalls;
  final int _clockTicksPerS;

  int _lastHb = 0;
  int _lastTickMs = Timeline.now ~/ 1000;
  int _heldMs = 0;
  _ThreadCpu? _start;
  final List<int> _counts = List.filled(probeClasses.length, 0);

  // Every [_samplePeriodMs] while LoopLag ticks; once a second while it
  // doesn't (app in the background, or diagnostics turned off).
  void schedule() {
    final idle = mem[_hb] <= 0 && _lastHb <= 0;
    Timer(Duration(milliseconds: idle ? 1000 : _samplePeriodMs), () {
      try {
        tick();
      } catch (_) {}
      schedule();
    });
  }

  void tick() {
    // Timeline.now is the same monotonic clock in every isolate.
    final now = Timeline.now ~/ 1000;
    // Run this late, the helper was held up too: the VM pauses every
    // isolate of the group at once (a garbage collection), or the whole
    // process was not scheduled.
    final late = now - _lastTickMs - _samplePeriodMs;
    _lastTickMs = now;
    if (late >= 300) _heldMs += late;
    final hb = mem[_hb];
    if (hb != _lastHb) {
      // The loop ran again: if the beats are a blocked tick apart (1 s
      // late), that was a block. Not when LoopLag stopped ticking (0).
      final apartMs = (hb - _lastHb) ~/ 1000;
      // Over a minute apart is a suspended system (or a debugger), not a
      // block: LoopLag leaves those out too.
      if (_lastHb > 0 &&
          hb > 0 &&
          apartMs >= _beatMs + 1000 &&
          apartMs <= _beatMs + 60000) {
        _finish(now, apartMs);
      }
      _lastHb = hb;
      _heldMs = 0;
      _start = null;
      _counts.fillRange(0, _counts.length, 0);
      return;
    }
    if (hb <= 0) return;
    final still = now - hb ~/ 1000;
    // The next beat is due [_beatMs] after the last one; give it some slack.
    if (still < _beatMs + 100) return;
    _sample();
    if (_start == null && still >= _beatMs + 600) _start = _threads(now);
  }

  void _finish(int now, int apartMs) {
    mem[_blocks] += 1;
    mem[_blockMs] += apartMs - _beatMs;
    if (_heldMs > 0) {
      mem[_pausedBlocks] += 1;
      mem[_pausedMs] += _heldMs;
    }
    for (var i = 0; i < _counts.length; i++) {
      mem[_classBase + i] += _counts[i];
    }
    final start = _start;
    final end = start == null ? null : _threads(now);
    if (start == null || end == null) return;
    final wallMs = end.atMs - start.atMs;
    int ms(int ticks) => ticks * 1000 ~/ _clockTicksPerS;
    var workers = 0, raster = 0, other = 0, busy = 0;
    end.ticks.forEach((tid, e) {
      if (tid == uiTid) return;
      final before = start.ticks[tid]?.$2 ?? 0;
      final d = ms(e.$2 - before);
      if (d <= 0) return;
      switch (e.$1) {
        case "worker":
          workers += d;
          if (wallMs > 0 && d * 2 >= wallMs) busy++;
        case "raster":
          raster += d;
        default:
          other += d;
      }
    });
    final ui = ms(end.uiTicks - start.uiTicks);
    mem[_cpuBlocks] += 1;
    mem[_cpuUi] += ui < 0 ? 0 : ui;
    mem[_cpuWorkers] += workers;
    mem[_cpuRaster] += raster;
    mem[_cpuOther] += other;
    mem[_workersBusy] += busy;
    final faults = end.majorFaults - start.majorFaults;
    mem[_majorFaults] += faults < 0 ? 0 : faults;
  }

  // One sample of the UI thread: its state and the system call it is in.
  void _sample() {
    String? syscall;
    String stat;
    try {
      stat = File("/proc/self/task/$uiTid/stat").readAsStringSync();
      if (probeThreadState(stat) == "S") {
        syscall = File("/proc/self/task/$uiTid/syscall").readAsStringSync();
      }
    } catch (_) {
      return _count("other");
    }
    _count(probeClassOf(stat, syscall, _syscalls, _fdKind));
  }

  void _count(String kind) {
    final i = probeClasses.indexOf(kind);
    _counts[i < 0 ? probeClasses.length - 1 : i]++;
  }

  static String _fdKind(int fd) {
    try {
      final target = Link("/proc/self/fd/$fd").targetSync();
      if (target.startsWith("socket:")) return "socket";
      if (target.startsWith("pipe:")) return "pipe";
      if (target.startsWith("/dev/dri/")) return "gpu";
      if (target.startsWith("/dev/")) return "dev";
      if (target.startsWith("/")) return "file";
    } catch (_) {}
    return "other";
  }

  // Every thread's CPU time, and the process's major page faults.
  _ThreadCpu? _threads(int now) {
    try {
      final ticks = <int, (String, int)>{};
      var ui = 0;
      for (final entry in Directory("/proc/self/task").listSync()) {
        final tid = int.tryParse(entry.path.split("/").last);
        if (tid == null) continue;
        String stat;
        try {
          stat = File("${entry.path}/stat").readAsStringSync();
        } catch (_) {
          continue; // the thread ended
        }
        final open = stat.indexOf("(");
        final close = stat.lastIndexOf(")");
        final comm = stat.substring(open + 1, close);
        final f = stat.substring(close + 2).split(" ");
        final cpu = int.parse(f[11]) + int.parse(f[12]);
        if (tid == uiTid) ui = cpu;
        final kind = comm == "DartWorker"
            ? "worker"
            : comm.contains("rast")
                ? "raster"
                : "other";
        ticks[tid] = (kind, cpu);
      }
      final self = File("/proc/self/stat").readAsStringSync();
      final f = self.substring(self.lastIndexOf(")") + 2).split(" ");
      return _ThreadCpu(now, ticks, ui, int.parse(f[9]));
    } catch (_) {
      return null;
    }
  }
}

/// A thread's state letter in its /proc stat line (R, S, D…).
String probeThreadState(String stat) {
  final close = stat.lastIndexOf(")");
  return close < 0 || close + 2 >= stat.length ? "?" : stat[close + 2];
}

/// The class ([probeClasses]) of a thread sample: its /proc stat line and,
/// when it sleeps, its /proc syscall line; [fdKind] says what a file
/// descriptor is (socket, pipe, file, gpu, dev, other).
String probeClassOf(String stat, String? syscall, Map<int, String> syscalls,
    String Function(int fd) fdKind) {
  final state = probeThreadState(stat);
  if (state == "R") return "run";
  if (state == "D") return "disk";
  if (syscall == null) return state == "S" ? "other" : "sleep";
  final sys = syscall.trim().split(" ");
  if (sys.first == "running") return "run";
  final nr = int.tryParse(sys.first);
  final kind = nr == null ? null : syscalls[nr];
  if (kind == null) return "other";
  if (kind == "read" || kind == "write" || kind == "ioctl") {
    final arg =
        sys.length > 1 && sys[1].startsWith("0x") ? sys[1].substring(2) : null;
    final fd = arg == null ? null : int.tryParse(arg, radix: 16);
    final file = fd == null || fd > 1 << 20 ? "other" : fdKind(fd);
    if (kind == "ioctl") return file == "gpu" ? "ioctl_gpu" : "ioctl_other";
    return "${kind}_${const {
      "socket",
      "pipe",
      "file"
    }.contains(file) ? file : "other"}";
  }
  return kind;
}

/// System call numbers by class, for the CPU's Linux ABI (others: none).
Map<int, String> probeSyscalls(Abi abi) {
  if (abi == Abi.linuxX64) {
    return {
      0: "read",
      17: "read",
      19: "read",
      45: "read",
      47: "read",
      295: "read",
      1: "write",
      18: "write",
      20: "write",
      44: "write",
      46: "write",
      296: "write",
      7: "poll",
      23: "poll",
      232: "poll",
      270: "poll",
      271: "poll",
      281: "poll",
      441: "poll",
      16: "ioctl",
      202: "futex",
      449: "futex",
      24: "sleep",
      35: "sleep",
      230: "sleep",
      61: "wait_child",
      247: "wait_child",
      74: "fsync",
      75: "fsync",
      277: "fsync",
      2: "open",
      257: "open",
      437: "open",
      9: "mem",
      11: "mem",
      12: "mem",
      25: "mem",
      28: "mem",
      72: "lock",
      73: "lock",
    };
  }
  if (abi == Abi.linuxArm64 || abi == Abi.linuxRiscv64) {
    return {
      63: "read",
      65: "read",
      67: "read",
      69: "read",
      207: "read",
      212: "read",
      64: "write",
      66: "write",
      68: "write",
      70: "write",
      206: "write",
      211: "write",
      72: "poll",
      73: "poll",
      22: "poll",
      441: "poll",
      29: "ioctl",
      98: "futex",
      449: "futex",
      124: "sleep",
      101: "sleep",
      115: "sleep",
      260: "wait_child",
      95: "wait_child",
      82: "fsync",
      83: "fsync",
      84: "fsync",
      56: "open",
      437: "open",
      222: "mem",
      215: "mem",
      214: "mem",
      216: "mem",
      233: "mem",
      25: "lock",
      32: "lock",
    };
  }
  return const {};
}
