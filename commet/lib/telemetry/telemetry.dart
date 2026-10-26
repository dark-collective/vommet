// Opt-in diagnostics (Vommet). Nothing is recorded or sent unless the user
// said yes on the consent screen (preferences.telemetryConsent == true).
//
// What can be sent is fixed by assets/telemetry/schema.json: timings, sizes,
// counts, yes/no values, values from fixed lists and code locations. Message
// text, media, file names, room/user/event IDs and error messages have no field
// to go in; events that don't match the schema are dropped here and again by
// the collector (vommet-proxy, POST /telemetry).
//
// Cost when enabled: record() validates and appends to an in-memory queue;
// one small HTTPS POST per minute at most, off the UI's critical path.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:commet/config/build_config.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/diagnostic/diagnostics.dart';
import 'package:commet/main.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/config/app_config.dart';
import 'package:commet/telemetry/exit_telemetry.dart';
import 'package:commet/telemetry/frame_stats.dart';
import 'package:commet/telemetry/get_users_telemetry.dart';
import 'package:commet/telemetry/loop_lag.dart';
import 'package:commet/telemetry/main_spans.dart';
import 'package:commet/telemetry/notify_counts.dart';
import 'package:commet/telemetry/repaint_stats.dart';
import 'package:commet/telemetry/reply_lookup_stats.dart';
import 'package:commet/telemetry/resume_telemetry.dart';
import 'package:commet/telemetry/sync_stats.dart';
import 'package:commet/telemetry/telemetry_errors.dart';
import 'package:commet/telemetry/telemetry_http.dart';
import 'package:commet/telemetry/telemetry_schema.dart';
import 'package:commet/telemetry/telemetry_tag.dart';
import 'package:path/path.dart' as p;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

class SentTelemetryBatch {
  final DateTime time;
  final String json;
  SentTelemetryBatch(this.time, this.json);
}

class Telemetry {
  static TelemetrySchema? _schema;

  /// Whether the loaded schema's enum [type] lists [value].
  static bool enumAllows(String type, String value) =>
      _schema?.enumAllows(type, value) ?? false;
  static final Stopwatch _clock = Stopwatch();
  static final String _session = const Uuid().v4();
  static Map<String, Object> _envelope = const {};

  static final List<Map<String, Object>> _queue = [];
  static const int _maxQueue = 1000;
  static bool _flushing = false;

  static Timer? _flushTimer;
  static Timer? _perfTimer;
  static AppLifecycleListener? _lifecycle;
  static _MemoryPressureObserver? _memoryObserver;

  /// Vommet (schema v17): events dropped by the schema check and events
  /// pushed out of a full queue since the last perf summary. Non-zero means
  /// a client bug or a schema mismatch is losing data.
  static int _dropped = 0;
  static int _overflow = 0;

  /// Open room timelines (MatrixTimeline counts itself in and out), for the
  /// memory figures in perf_summary.
  static int timelinesLive = 0;

  /// Whether the view-dependent envelope fields (screen, text scale) have
  /// been filled in; they need a window, which may not exist at init.
  static bool _lateEnvelopeDone = false;

  static final Map<String, int> _crashCounts = {};

  /// Most recent successfully sent batches, newest last, for the
  /// "What's been sent" page.
  static final List<SentTelemetryBatch> sent = [];
  static const int _maxSent = 50;
  static final StreamController<void> _sentChanged =
      StreamController.broadcast();
  static Stream<void> get onSentChanged => _sentChanged.stream;

  static bool get enabled =>
      _schema != null && preferences.telemetryConsent.value == true;

  /// Milliseconds since this app session started.
  static int get sinceStart => _clock.elapsedMilliseconds;

  static Future<void> init() async {
    _clock.start();
    try {
      _schema = TelemetrySchema.parse(
          await rootBundle.loadString("assets/telemetry/schema.json"));
      _envelope = await _buildEnvelope();
    } catch (e, s) {
      _schema = null;
      Log.onError(e, s, content: "Telemetry disabled: could not load schema");
      return;
    }
    preferences.telemetryConsent.onChanged.listen((_) => _applyConsent());
    await _applyConsent();
  }

  static Future<void> _applyConsent() async {
    // Vommet: the UI isolate's spans only count with consent.
    MainSpans.enabled = enabled;
    if (enabled) {
      if (preferences.telemetryInstallId.value == null) {
        await preferences.telemetryInstallId.set(const Uuid().v4());
      }
      _flushTimer ??=
          Timer.periodic(const Duration(seconds: 60), (_) => flush());
      _perfTimer ??= Timer.periodic(
          const Duration(minutes: 15), (_) => _recordPerfSummary());
      _lifecycle ??= AppLifecycleListener(
        onHide: _backgroundFlush,
        onPause: _backgroundFlush,
        onDetach: _backgroundFlush,
      );
      FrameStats.start();
      RepaintStats.setTelemetry(true);
      LoopLag.start();
      ResumeTelemetry.start();
      SyncStats.start();
      if (_memoryObserver == null) {
        _memoryObserver = _MemoryPressureObserver();
        WidgetsBinding.instance.addObserver(_memoryObserver!);
      }
      ExitTelemetry.reportPreviousExit();
    } else {
      _flushTimer?.cancel();
      _flushTimer = null;
      _perfTimer?.cancel();
      _perfTimer = null;
      _lifecycle?.dispose();
      _lifecycle = null;
      FrameStats.stop();
      RepaintStats.setTelemetry(false);
      LoopLag.stop();
      ResumeTelemetry.stop();
      SyncStats.stop();
      HttpStats.reset();
      HttpStats.clearErrors();
      ReplyLookupStats.reset();
      if (_memoryObserver != null) {
        WidgetsBinding.instance.removeObserver(_memoryObserver!);
        _memoryObserver = null;
      }
      _dropped = _overflow = 0;
      _queue.clear();
      // Vommet: notification counters are only kept while consented.
      unawaited(NotifyCounts.clear());
    }
  }

  /// Record one event. [fields] with null values are left out. Invalid events
  /// are dropped (and logged by name only, never by content).
  static void record(String event, Map<String, Object?> fields) {
    if (!enabled) return;
    final ev = <String, Object>{"e": event, "t": sinceStart};
    fields.forEach((k, v) {
      if (v != null) ev[k] = v;
    });
    if (!_schema!.validateEvent(ev)) {
      _dropped++;
      if (kDebugMode || preferences.developerMode.value) {
        Log.w("Telemetry: dropped invalid '$event' event "
            "(fields: ${fields.keys.join(", ")})");
      }
      return;
    }
    if (_queue.length >= _maxQueue) {
      _queue.removeAt(0);
      _overflow++;
    }
    _queue.add(ev);
  }

  /// Outcome fields for an operation: {"outcome": "ok"} when [error] is null,
  /// else outcome/error_kind/error_type/http_status/errcode derived from it.
  static Map<String, Object?> errorFields(Object? error,
      {bool withType = true, bool withStatus = true}) {
    if (error == null) return {"outcome": "ok"};
    final kind = TelemetryErrors.kind(error);
    return {
      "outcome": "error",
      "error_kind": kind,
      if (withType) "error_type": TelemetryErrors.typeName(error),
      if (withStatus) "http_status": TelemetryErrors.httpStatus(error),
      if (withStatus && TelemetryErrors.errcode(error) != null)
        "errcode": TelemetryErrors.errcode(error),
    };
  }

  /// Unhandled or logged errors. Deduplicated by type + top frame: the first
  /// occurrence is sent, then the 10th, 100th and 1000th with a repeat count.
  static void recordCrash(Object error, StackTrace? trace,
      {required String source, bool fatal = false}) {
    if (!enabled) return;
    final frames = TelemetryErrors.frames(trace);
    // Vommet (schema v18): Android release traces are non-symbolic, so
    // `frames` is empty there; send the build id and offsets instead.
    final dart = frames.isEmpty ? TelemetryErrors.dartPcs(trace) : null;
    final type = TelemetryErrors.typeName(error);
    final top = frames.isNotEmpty
        ? frames.first
        : dart != null
            ? dart.pcs.first
            : "";
    final key = "$type@$top";
    final n = (_crashCounts[key] ?? 0) + 1;
    if (_crashCounts.length < 500 || _crashCounts.containsKey(key)) {
      _crashCounts[key] = n;
    }
    if (n == 1 || n == 10 || n == 100 || n == 1000 || fatal) {
      record("crash", {
        "source": source,
        "fatal": fatal,
        "error_type": type,
        "frames": frames,
        if (dart != null) "dart_build_id": dart.buildId,
        if (dart != null) "dart_pcs": dart.pcs,
        if (TelemetryErrors.httpStatus(error) != null)
          "http_status": TelemetryErrors.httpStatus(error),
        if (TelemetryErrors.errcode(error) != null)
          "errcode": TelemetryErrors.errcode(error),
        if (n > 1) "repeat": n,
      });
      if (fatal) flush();
    }
  }

  /// Timer names from [Diagnostics] that are plain code identifiers; anything
  /// else (e.g. a name with an account id folded in) is left out.
  static final _codeName = RegExp(r"^[A-Za-z_][A-Za-z0-9_]{0,63}$");

  /// Vommet (schema v17): the general timers' names are English phrases
  /// ("Startup: accounts loaded", "Open room (load timeline)"), so only
  /// `loadFromDB` ever passed the identifier check and the startup steps
  /// never shipped. Each known phrase is made an identifier; a name not on
  /// this list is left out, because one of them folds an account's client
  /// name in ("Initializing client <name>"). Add a literal here when adding
  /// a timer that should ship.
  static const Set<String> knownGeneralTimers = {
    "loadFromDB",
    "Startup_preferences",
    "Startup_database_server",
    "Startup_file_cache_config",
    "Startup_accounts_loaded",
    "Startup_room_list_on_screen_since_launch",
    "Startup_splash_held_for_room_state",
    "Startup_first_frame_since_launch",
    "Deferred_room_state_loads",
    "Matrix_client_init",
    "Open_room_load_timeline",
    "Load_older_messages",
    "Deferred_room_state_query",
    "Deferred_room_state_apply",
    "Room_list_update",
    "Space_rooms_list_update",
    "Deferred_room_state_callbacks",
  };

  /// A timer phrase as an identifier: runs of anything but letters, digits
  /// and underscores become one underscore; leading/trailing ones are cut.
  /// A trailing room count ("Deferred room state loads (209 rooms)") is
  /// dropped so the name stays fixed.
  static String timerName(String name) => name
      .replaceFirst(_dbPrefix, "")
      .trim()
      .replaceAll(RegExp(r"[^A-Za-z0-9_]+"), "_")
      .replaceAll(RegExp(r"^_+|_+$"), "")
      .replaceFirst(RegExp(r"_\d+_rooms$"), "");

  static List<Map<String, Object>> timers(CumulativeDiagnostics d) {
    final out = <Map<String, Object>>[];
    for (final m in d.measurements.values) {
      final name = timerName(m.name);
      if (!knownGeneralTimers.contains(name) || !_codeName.hasMatch(name)) {
        continue;
      }
      out.add(<String, Object>{
        "name": name,
        "calls": m.numCalls.clamp(0, 1000000),
        "total_ms": m.totalDuration.inMilliseconds.clamp(0, 86400000),
      });
      if (out.length == 64) break;
    }
    return out;
  }

  /// Vommet (schema v14): the database layer's timers. Their names are fixed
  /// English phrases ("Store event update"), so they never passed [timers]'
  /// identifier check and the app_ready database timings always shipped
  /// empty. The database package prefixes each name with the first letters
  /// of the account's client name, "(abcd) - "; that prefix is cut off here
  /// (it could carry part of an account id) and the accounts' entries for
  /// one operation are summed. The phrases come from a closed list in the
  /// database package, so they are made identifiers; anything still not one
  /// is left out. With [since], only the calls and time added after that
  /// snapshot are reported, and the snapshot is updated.
  static final _dbPrefix = RegExp(r"^\([^)]*\)\s*-\s*");
  static List<Map<String, Object>> dbTimers(
    CumulativeDiagnostics d, {
    Map<String, (int, int)>? since,
  }) {
    final totals = <String, (int, int)>{};
    for (final m in d.measurements.values) {
      final name = m.name
          .replaceFirst(_dbPrefix, "")
          .trim()
          .replaceAll(RegExp(r"[^A-Za-z0-9_]+"), "_");
      if (!_codeName.hasMatch(name)) continue;
      final (calls, ms) = totals[name] ?? (0, 0);
      totals[name] = (calls + m.numCalls, ms + m.totalDuration.inMilliseconds);
    }
    final out = <Map<String, Object>>[];
    for (final MapEntry(key: name, value: (totalCalls, totalMs))
        in totals.entries) {
      var calls = totalCalls;
      var ms = totalMs;
      if (since != null) {
        final (prevCalls, prevMs) = since[name] ?? (0, 0);
        since[name] = (totalCalls, totalMs);
        calls -= prevCalls;
        ms -= prevMs;
        if (calls <= 0) continue;
      }
      out.add(<String, Object>{
        "name": name,
        "calls": calls.clamp(0, 1000000),
        "total_ms": ms.clamp(0, 86400000),
      });
      if (out.length == 64) break;
    }
    return out;
  }

  /// Database timer totals at the last perf summary, per timer name.
  static final Map<String, (int, int)> _dbSince = {};

  static int? _rssMb() {
    try {
      return ProcessInfo.currentRss ~/ (1024 * 1024);
    } catch (_) {
      return null;
    }
  }

  /// Vommet (schema v17): the accounts' database files on disk, in MB
  /// (data.db plus its write-ahead log), one stat per file per summary.
  static Future<int?> databaseMb() async {
    if (BuildConfig.WEB) return null;
    try {
      final dir = await AppConfig.getDriftDatabasePath();
      var bytes = 0;
      final clients = clientManager?.clients.whereType<MatrixClient>() ??
          const Iterable<MatrixClient>.empty();
      for (final client in clients) {
        final name = client.getMatrixClient().clientName;
        for (final f in ["data.db", "data.db-wal"]) {
          final file = File(p.join(dir, name, f));
          if (await file.exists()) bytes += await file.length();
        }
      }
      return (bytes ~/ (1024 * 1024)).clamp(0, 1000000);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _recordPerfSummary() async {
    FrameStats.report();
    RepaintStats.report();
    LoopLag.report();
    SyncStats.report();
    HttpStats.report();
    ReplyLookupStats.report();
    final dbMb = await databaseMb();
    // Vommet (schema v15): Flutter's decoded-image cache, to tell whether it
    // is behind the memory Linux testers report (545-894 MB, one at 2 GB).
    final images = PaintingBinding.instance.imageCache;
    record("perf_summary", {
      "uptime_s": (sinceStart ~/ 1000).clamp(0, 2592000),
      "rss_mb": _rssMb(),
      "image_cache_mb": images.currentSizeBytes ~/ (1024 * 1024),
      "image_cache_max_mb": images.maximumSizeBytes ~/ (1024 * 1024),
      "image_cache_count": images.currentSize,
      "image_cache_live": images.liveImageCount,
      "image_cache_pending": images.pendingImageCount,
      // Vommet: plus the UI isolate's spans since the previous summary
      // (Main_*, Stall_*; no schema change: more timers).
      "timers": MainSpans.appendInterval(timers(Diagnostics.general)),
      // Vommet: plus the rooms' member loads (Get_users_room*, no schema
      // change: two more timers).
      "db": GetUsersTelemetry.appendTo(
          dbTimers(Diagnostics.postLoadDatabaseDiagnostics, since: _dbSince)),
      // Vommet (schema v17).
      "timelines_live": timelinesLive.clamp(0, 1000000),
      "db_mb": dbMb,
      "dropped": _dropped.clamp(0, 1000000),
      "overflow": _overflow.clamp(0, 1000000),
      "clock_skew_s": HttpStats.clockSkewS,
    });
    _dropped = _overflow = 0;
  }

  /// Vommet (schema v17): the OS asked us to free memory (Android's
  /// onTrimMemory, iOS memory warnings). Where the memory sits at that
  /// moment is the question these figures answer.
  static void recordMemoryPressure() {
    if (!enabled) return;
    final images = PaintingBinding.instance.imageCache;
    final state = WidgetsBinding.instance.lifecycleState;
    record("memory_pressure", {
      "uptime_s": (sinceStart ~/ 1000).clamp(0, 2592000),
      "rss_mb": _rssMb(),
      "image_cache_mb": images.currentSizeBytes ~/ (1024 * 1024),
      "timelines_live": timelinesLive.clamp(0, 1000000),
      "foreground": state == null || state == AppLifecycleState.resumed,
    });
  }

  /// Vommet (schema v22): the app is going to the background, where it may
  /// be killed: hand in the small counters that otherwise wait for the
  /// 15-minute summary, then send what is queued.
  static void _backgroundFlush() {
    if (!enabled) return;
    ReplyLookupStats.report();
    unawaited(flush());
  }

  static Future<void> flush() async {
    if (!enabled || _flushing || _queue.isEmpty) return;
    _flushing = true;
    if (!_lateEnvelopeDone) _fillLateEnvelope();
    final take = _queue.length.clamp(0, _schema!.maxEvents);
    final events = _queue.sublist(0, take);
    _queue.removeRange(0, take);
    try {
      final batch = <String, Object>{
        ..._envelope,
        "install": preferences.telemetryInstallId.value!,
        "session": _session,
        if (TelemetryTag.normalize(preferences.telemetryTag.value)
            case final tag?)
          "tag": tag,
        "events": events,
      };
      final envelope = Map<String, dynamic>.from(batch)..remove("events");
      if (!_schema!.validateEnvelope(envelope)) {
        Log.w("Telemetry: invalid envelope, batch dropped");
        return;
      }
      final body = jsonEncode(batch);
      final resp = await http
          .post(Uri.https(preferences.proxyUrl.value, "/telemetry"),
              headers: {"Content-Type": "application/json"}, body: body)
          .timeout(const Duration(seconds: 20));
      if (resp.statusCode == 202) {
        sent.add(SentTelemetryBatch(
            DateTime.now(), const JsonEncoder.withIndent("  ").convert(batch)));
        if (sent.length > _maxSent) sent.removeAt(0);
        _sentChanged.add(null);
      } else if (resp.statusCode == 429 || resp.statusCode >= 500) {
        _requeue(events);
      } else {
        // 400/413: the batch itself is wrong; resending won't help.
        Log.w("Telemetry: collector refused a batch (${resp.statusCode})");
      }
    } catch (_) {
      _requeue(events);
    } finally {
      _flushing = false;
    }
  }

  static void _requeue(List<Map<String, Object>> events) {
    if (!enabled) return;
    _queue.insertAll(0, events);
    while (_queue.length > _maxQueue) {
      _queue.removeAt(0);
    }
  }

  /// Ask the collector to delete everything stored for this install, then
  /// start over with a new random ID. Returns true when the collector
  /// confirmed the deletion.
  static Future<bool> deleteMyData() async {
    final id = preferences.telemetryInstallId.value;
    _queue.clear();
    await NotifyCounts.clear();
    if (id == null) return true;
    try {
      final resp = await http
          .delete(
              Uri.https(preferences.proxyUrl.value, "/telemetry/install/$id"))
          .timeout(const Duration(seconds: 30));
      if (resp.statusCode != 200) return false;
    } catch (_) {
      return false;
    }
    await resetInstallId();
    return true;
  }

  static Future<void> resetInstallId() async {
    _queue.clear();
    sent.clear();
    _sentChanged.add(null);
    await preferences.telemetryInstallId
        .set(enabled ? const Uuid().v4() : null);
  }

  static final _versionPattern = RegExp(r"^[A-Za-z0-9._+/-]{1,80}$");

  /// The build's version label in the schema's character set. Tester builds
  /// are labelled like "testing-2026-10-08b (1754)" (release name and CI run
  /// number), which the old check turned into "unknown"; that becomes
  /// "testing-2026-10-08b+1754".
  static String versionLabel(String tag) {
    var v = tag
        .trim()
        .replaceAllMapped(RegExp(r"\s*\((\d+)\)$"), (m) => "+${m[1]}")
        .replaceAll(RegExp(r"\s+"), "_");
    return _versionPattern.hasMatch(v) ? v : "unknown";
  }

  /// Vommet (schema v17): screen size, pixel density and accessibility
  /// settings that change layout, read once a window exists. Zero sizes mean
  /// no window yet; try again at the next flush.
  static void _fillLateEnvelope() {
    try {
      final dispatcher = WidgetsBinding.instance.platformDispatcher;
      final views = dispatcher.views;
      final view = views.isEmpty ? null : views.first;
      if (view == null || view.physicalSize.isEmpty) return;
      final a11y = dispatcher.accessibilityFeatures;
      _envelope = {
        ..._envelope,
        "screen_w": view.physicalSize.width.round().clamp(0, 100000),
        "screen_h": view.physicalSize.height.round().clamp(0, 100000),
        "dpr_x100": (view.devicePixelRatio * 100).round().clamp(0, 2000),
        "text_scale_x100":
            (dispatcher.textScaleFactor * 100).round().clamp(0, 1000),
        "bold_text": a11y.boldText,
        "reduce_motion": a11y.disableAnimations,
        "high_contrast": a11y.highContrast,
      };
      _lateEnvelopeDone = true;
    } catch (_) {}
  }

  /// The schema's `desktop` value for a Linux `XDG_CURRENT_DESKTOP`.
  static String desktopKind(String? xdg) {
    if (xdg == null || xdg.isEmpty) return "unknown";
    final v = xdg.toLowerCase();
    for (final (needle, kind) in const [
      ("gnome", "gnome"),
      ("ubuntu", "gnome"),
      ("kde", "kde"),
      ("plasma", "kde"),
      ("xfce", "xfce"),
      ("cinnamon", "cinnamon"),
      ("mate", "mate"),
      ("lxqt", "lxqt"),
      ("lxde", "lxde"),
      ("budgie", "budgie"),
      ("cosmic", "cosmic"),
      ("pantheon", "pantheon"),
      ("deepin", "deepin"),
      ("sway", "sway"),
      ("hyprland", "hyprland"),
      ("i3", "i3"),
    ]) {
      if (v.contains(needle)) return kind;
    }
    return "other";
  }

  /// Total memory in MB from /proc/meminfo's MemTotal line (kB).
  static int? memTotalMb(List<String> meminfo) {
    for (final line in meminfo) {
      final m = RegExp(r"^MemTotal:\s+(\d+)\s*kB").firstMatch(line);
      if (m != null) return int.parse(m.group(1)!) ~/ 1024;
    }
    return null;
  }

  static Future<Map<String, Object>> _buildEnvelope() async {
    final version = versionLabel(BuildConfig.VERSION_TAG);
    int? ramMb;
    bool? lowRam;
    String? desktop;
    bool? glSoftware;

    String flavor;
    if (kDebugMode) {
      flavor = "debug";
    } else if (kProfileMode) {
      flavor = "profile";
    } else if (RegExp(r"^v\d").hasMatch(BuildConfig.VERSION_TAG)) {
      flavor = "release";
    } else {
      flavor = "testing";
    }

    String platform;
    String display;
    String packaging = "unknown";
    int? osBuild;
    String? osId;
    if (BuildConfig.WEB) {
      platform = "web";
      display = "web";
    } else if (Platform.isWindows) {
      platform = "windows";
      display = "windows";
      packaging = "zip";
      final m =
          RegExp(r"Build (\d+)").firstMatch(Platform.operatingSystemVersion);
      if (m != null) osBuild = int.tryParse(m.group(1)!);
      try {
        ramMb = (await DeviceInfoPlugin().windowsInfo).systemMemoryInMegabytes;
      } catch (_) {}
    } else if (Platform.isAndroid) {
      platform = "android";
      display = "android";
      packaging = "apk";
      try {
        final info = await DeviceInfoPlugin().androidInfo;
        osBuild = info.version.sdkInt;
        ramMb = info.physicalRamSize;
        lowRam = info.isLowRamDevice;
      } catch (_) {}
    } else if (Platform.isLinux) {
      platform = "linux";
      final env = Platform.environment;
      display = env.containsKey("WAYLAND_DISPLAY")
          ? "wayland"
          : env.containsKey("DISPLAY")
              ? "x11"
              : "unknown";
      packaging = BuildConfig.IS_FLATPAK || env.containsKey("FLATPAK_ID")
          ? "flatpak"
          : "unknown";
      try {
        // Inside the Flatpak /etc/os-release is the runtime's
        // ("org.gnome.platform"); Flatpak mounts the host's at
        // /run/host/os-release.
        final host = File("/run/host/os-release");
        final release = await (packaging == "flatpak" && await host.exists()
                ? host
                : File("/etc/os-release"))
            .readAsLines();
        final id = release
            .firstWhere((l) => l.startsWith("ID="), orElse: () => "")
            .replaceFirst("ID=", "")
            .replaceAll('"', "")
            .toLowerCase();
        if (RegExp(r"^[a-z0-9._-]{1,32}$").hasMatch(id)) osId = id;
      } catch (_) {}
      desktop = desktopKind(env["XDG_CURRENT_DESKTOP"]);
      glSoftware = const ["1", "true"]
          .contains(env["LIBGL_ALWAYS_SOFTWARE"]?.toLowerCase());
      try {
        ramMb = memTotalMb(await File("/proc/meminfo").readAsLines());
      } catch (_) {}
    } else if (Platform.isMacOS) {
      platform = "macos";
      display = "macos";
    } else {
      platform = "ios";
      display = "ios";
    }

    return {
      "v": _schema!.version,
      "app_version": version,
      "flavor": flavor,
      "platform": platform,
      "display": display,
      "packaging": packaging,
      if (osBuild != null && osBuild >= 0 && osBuild <= 10000000)
        "os_build": osBuild,
      if (osId != null) "os_id": osId,
      if (!BuildConfig.WEB) "cpu_cores": Platform.numberOfProcessors,
      if (ramMb != null && ramMb >= 0 && ramMb <= 10000000) "ram_mb": ramMb,
      if (lowRam != null) "low_ram": lowRam,
      if (desktop != null) "desktop": desktop,
      if (glSoftware != null) "gl_software": glSoftware,
    };
  }
}

class _MemoryPressureObserver with WidgetsBindingObserver {
  @override
  void didHaveMemoryPressure() => Telemetry.recordMemoryPressure();
}
