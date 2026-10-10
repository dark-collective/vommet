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
import 'package:commet/telemetry/exit_telemetry.dart';
import 'package:commet/telemetry/frame_stats.dart';
import 'package:commet/telemetry/loop_lag.dart';
import 'package:commet/telemetry/notify_counts.dart';
import 'package:commet/telemetry/sync_stats.dart';
import 'package:commet/telemetry/telemetry_errors.dart';
import 'package:commet/telemetry/telemetry_schema.dart';
import 'package:commet/telemetry/telemetry_tag.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
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
    if (enabled) {
      if (preferences.telemetryInstallId.value == null) {
        await preferences.telemetryInstallId.set(const Uuid().v4());
      }
      _flushTimer ??=
          Timer.periodic(const Duration(seconds: 60), (_) => flush());
      _perfTimer ??= Timer.periodic(
          const Duration(minutes: 15), (_) => _recordPerfSummary());
      _lifecycle ??= AppLifecycleListener(
        onHide: flush,
        onPause: flush,
        onDetach: flush,
      );
      FrameStats.start();
      LoopLag.start();
      ExitTelemetry.reportPreviousExit();
    } else {
      _flushTimer?.cancel();
      _flushTimer = null;
      _perfTimer?.cancel();
      _perfTimer = null;
      _lifecycle?.dispose();
      _lifecycle = null;
      FrameStats.stop();
      LoopLag.stop();
      SyncStats.reset();
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
      if (kDebugMode || preferences.developerMode.value) {
        Log.w("Telemetry: dropped invalid '$event' event "
            "(fields: ${fields.keys.join(", ")})");
      }
      return;
    }
    if (_queue.length >= _maxQueue) _queue.removeAt(0);
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
    final type = TelemetryErrors.typeName(error);
    final key = "$type@${frames.isEmpty ? "" : frames.first}";
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
  static List<Map<String, Object>> timers(CumulativeDiagnostics d) {
    return d.measurements.values
        .where((m) => _codeName.hasMatch(m.name))
        .take(64)
        .map((m) => <String, Object>{
              "name": m.name,
              "calls": m.numCalls.clamp(0, 1000000),
              "total_ms": m.totalDuration.inMilliseconds.clamp(0, 86400000),
            })
        .toList();
  }

  static void _recordPerfSummary() {
    FrameStats.report();
    LoopLag.report();
    SyncStats.report();
    int? rssMb;
    try {
      rssMb = ProcessInfo.currentRss ~/ (1024 * 1024);
    } catch (_) {}
    record("perf_summary", {
      "uptime_s": (sinceStart ~/ 1000).clamp(0, 2592000),
      "rss_mb": rssMb,
      "timers": timers(Diagnostics.general),
    });
  }

  static Future<void> flush() async {
    if (!enabled || _flushing || _queue.isEmpty) return;
    _flushing = true;
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

  static Future<Map<String, Object>> _buildEnvelope() async {
    final version = versionLabel(BuildConfig.VERSION_TAG);

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
    } else if (Platform.isAndroid) {
      platform = "android";
      display = "android";
      packaging = "apk";
      try {
        osBuild = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
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
        final release = await File("/etc/os-release").readAsLines();
        final id = release
            .firstWhere((l) => l.startsWith("ID="), orElse: () => "")
            .replaceFirst("ID=", "")
            .replaceAll('"', "")
            .toLowerCase();
        if (RegExp(r"^[a-z0-9._-]{1,32}$").hasMatch(id)) osId = id;
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
    };
  }
}
