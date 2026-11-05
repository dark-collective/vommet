// Vommet issue 825: did the previous desktop session end uncleanly (native
// crash, force-quit after a hang, power loss)? The process dies before Dart
// can record anything, so while the app runs a small marker file in the app
// support dir says "running", with a heartbeat about once a minute and the
// coarse call state. A clean exit (window close, quit menu or tray quit,
// update restart) marks it "clean". On the next launch a marker still saying
// "running" becomes `exit_reason` with reason "unclean", the seconds since
// its last heartbeat, the version that ran and its state flags. Never paths,
// messages or identifiers.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:commet/client/call_manager.dart';
import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/telemetry/telemetry.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// The coarse state the marker keeps current.
class SessionFlags {
  const SessionFlags(
      {this.inCall = false, this.screenShare = false, this.camera = false});

  final bool inCall;
  final bool screenShare;
  final bool camera;

  /// The flags of the calls we're in (ringing and ended calls don't count).
  static SessionFlags fromCalls(Iterable<VoipSession> sessions) {
    final live = sessions
        .where(
            (s) => s.state != VoipState.ended && s.state != VoipState.incoming)
        .toList();
    return SessionFlags(
      inCall: live.isNotEmpty,
      screenShare: live.any((s) => s.isSharingScreen),
      camera: live.any((s) => s.isCameraEnabled),
    );
  }
}

class SessionMarker {
  SessionMarker(this.file,
      {required this.version,
      required this.flags,
      DateTime Function()? now,
      this.heartbeat = const Duration(minutes: 1)})
      : _now = now ?? DateTime.now;

  final File file;
  final String version;
  final SessionFlags Function() flags;
  final DateTime Function() _now;
  final Duration heartbeat;

  Timer? _timer;
  int _start = 0;

  /// The `exit_reason` fields for the marker the last run left behind, or
  /// null when it exited cleanly (or there is no readable marker).
  Map<String, Object?>? previousUnclean() {
    try {
      if (!file.existsSync()) return null;
      final m = jsonDecode(file.readAsStringSync());
      if (m is! Map || m["state"] != "running") return null;
      final beat = m["beat"];
      final ran = m["version"];
      return {
        "reason": "unclean",
        "age": beat is int
            ? ((_now().millisecondsSinceEpoch - beat) ~/ 1000).clamp(0, 2592000)
            : null,
        "version": ran is String ? Telemetry.versionLabel(ran) : null,
        "in_call": m["in_call"] == true,
        "screen_share": m["screen_share"] == true,
        "camera": m["camera"] == true,
      };
    } catch (_) {
      return null;
    }
  }

  /// Writes the "running" marker and refreshes it every [heartbeat].
  void begin() {
    _start = _now().millisecondsSinceEpoch;
    _write("running");
    _timer?.cancel();
    _timer = Timer.periodic(heartbeat, (_) => refresh());
  }

  /// Rewrites the marker with a new heartbeat and the current flags.
  void refresh() {
    if (_timer != null) _write("running");
  }

  /// Marks the session clean and stops the heartbeat. Synchronous, so it is
  /// written before the process exits.
  void markClean() {
    if (_timer == null) return;
    _timer!.cancel();
    _timer = null;
    _write("clean");
  }

  /// Stops and removes the marker (telemetry was turned off).
  void stop() {
    _timer?.cancel();
    _timer = null;
    try {
      if (file.existsSync()) file.deleteSync();
    } catch (_) {}
  }

  void _write(String state) {
    try {
      final f = flags();
      final tmp = File("${file.path}.tmp");
      tmp.parent.createSync(recursive: true);
      tmp.writeAsStringSync(jsonEncode({
        "state": state,
        "start": _start,
        "beat": _now().millisecondsSinceEpoch,
        "version": version,
        "in_call": f.inCall,
        "screen_share": f.screenShare,
        "camera": f.camera,
      }));
      tmp.renameSync(file.path);
    } catch (e) {
      Log.w("Session marker: could not write: $e");
    }
  }
}

/// The app's marker: started with telemetry consent on desktop.
class SessionMarkerTelemetry {
  static SessionMarker? _marker;
  static CallManager? _calls;
  static final List<StreamSubscription> _listSubs = [];
  static final Map<VoipSession, StreamSubscription> _sessionSubs = {};
  static AppLifecycleListener? _macQuit;

  static bool get _desktop =>
      !PlatformUtils.isWeb &&
      (Platform.isLinux || Platform.isWindows || Platform.isMacOS);

  static Future<File> _file() async => File(p.join(
      (await getApplicationSupportDirectory()).path, "session_marker.json"));

  static Future<void> start(String version) async {
    if (_marker != null || !_desktop) return;
    try {
      final marker =
          SessionMarker(await _file(), version: version, flags: _flags);
      _marker = marker;
      final previous = marker.previousUnclean();
      if (previous != null) Telemetry.record("exit_reason", previous);
      marker.begin();
      // macOS quits (Cmd+Q, the menu, closing the last window) go through
      // the app delegate, not WindowManagement.quit. Not on Linux/Windows:
      // their close button may only minimize or hide to the tray.
      if (Platform.isMacOS) {
        _macQuit ??= AppLifecycleListener(onExitRequested: () async {
          markClean();
          return AppExitResponse.exit;
        });
      }
    } catch (e, s) {
      Log.onError(e, s, content: "Could not start the session marker");
    }
  }

  static SessionFlags _flags() => SessionFlags.fromCalls(
      (_calls ?? clientManager?.callManager)?.currentSessions ?? []);

  /// Rewrites the marker as soon as a call starts or ends or its camera or
  /// screen share changes. Call once the CallManager exists (Telemetry.init
  /// runs before it). Stays attached whatever the consent; [refresh] is a
  /// no-op while there is no marker, so consent turned on later works too.
  static void watchCalls(CallManager calls) {
    if (identical(_calls, calls)) return;
    _unwatchCalls();
    _calls = calls;
    final list = calls.currentSessions;
    list.forEach(_watchSession);
    _listSubs.add(list.onAdd.listen(_watchSession));
    _listSubs.add(list.onRemove.listen((session) {
      _sessionSubs.remove(session)?.cancel();
    }));
    _listSubs.add(list.onListUpdated.listen((_) => refresh()));
    refresh();
  }

  static void _watchSession(VoipSession session) {
    _sessionSubs[session] ??= session.onStateChanged.listen((_) => refresh());
  }

  static void _unwatchCalls() {
    for (final s in [..._listSubs, ..._sessionSubs.values]) {
      s.cancel();
    }
    _listSubs.clear();
    _sessionSubs.clear();
    _calls = null;
  }

  /// Sessions currently watched (tests).
  static int get watchedSessions => _sessionSubs.length;

  /// Rewrites the marker now (a call started, ended or changed).
  static void refresh() => _marker?.refresh();

  /// Call on every clean exit path, before the process ends.
  static void markClean() => _marker?.markClean();

  /// Telemetry is off: no marker, and none left from an earlier run.
  static Future<void> stop() async {
    _macQuit?.dispose();
    _macQuit = null;
    final marker = _marker;
    _marker = null;
    if (marker != null) {
      marker.stop();
      return;
    }
    if (!_desktop) return;
    try {
      final file = await _file();
      if (file.existsSync()) file.deleteSync();
    } catch (_) {}
  }
}
