// Vommet telemetry schema v43 (Vommet issue 825): the desktop unclean-exit
// marker. A session that died without a clean exit leaves its marker saying
// "running"; the next launch turns it into exit_reason "unclean" with the
// seconds since the last heartbeat, the version and the call state. Clean
// exits (exitApp: window close, quit menu, tray quit, update install) mark
// it clean.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:commet/client/call_manager.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/client/stale_info.dart';
import 'package:commet/main.dart';
import 'package:commet/telemetry/session_marker.dart';
import 'package:commet/telemetry/telemetry_schema.dart';
import 'package:commet/utils/app_exit.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeSession implements VoipSession {
  _FakeSession(this.state,
      {this.isSharingScreen = false, this.isCameraEnabled = false});

  @override
  VoipState state;
  @override
  bool isSharingScreen;
  @override
  bool isCameraEnabled;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Like MatrixLivekitVoipSession: toggling the camera or a screen share
/// fires onStateChanged (its _stateChanged, after _startShare / setCamera).
class _LiveSession implements VoipSession {
  final _changed = StreamController<void>.broadcast();

  @override
  VoipState state = VoipState.connected;
  @override
  bool isSharingScreen = false;
  @override
  bool isCameraEnabled = false;
  @override
  Stream<void> get onStateChanged => _changed.stream;

  void share(bool on) {
    isSharingScreen = on;
    _changed.add(null);
  }

  void camera(bool on) {
    isCameraEnabled = on;
    _changed.add(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ClientManager implements ClientManager {
  @override
  StreamController<int> onClientAdded = StreamController.broadcast();
  @override
  StreamController<StalePeerInfo> onClientRemoved =
      StreamController.broadcast();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Exited implements Exception {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final schema = TelemetrySchema.parse(
      File("assets/telemetry/schema.json").readAsStringSync());

  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync("marker"));
  tearDown(() => dir.deleteSync(recursive: true));

  test("schema is v43 and exit_reason takes unclean", () {
    expect(schema.version, greaterThanOrEqualTo(43));
    expect(schema.hasEvent("exit_reason"), isTrue);
  });

  test("a running marker from the last session becomes exit_reason unclean",
      () {
    var now = DateTime.utc(2026, 10, 26, 20, 0);
    final file = File("${dir.path}/session_marker.json");
    // The tester's sessions: in a call with a screen share when it died.
    final crashed = SessionMarker(file,
        version: "testing-2026-10-26g",
        flags: () => SessionFlags.fromCalls([
              _FakeSession(VoipState.connected, isSharingScreen: true),
            ]),
        now: () => now);
    crashed.begin();
    now = now.add(const Duration(seconds: 45));
    crashed.refresh();
    // No clean exit. The next launch, 2.5 minutes after the last heartbeat
    // (the issue's 2-3 minute gaps).
    now = now.add(const Duration(seconds: 150));
    final next = SessionMarker(file,
        version: "testing-2026-10-26g",
        flags: () => const SessionFlags(),
        now: () => now);
    final fields = next.previousUnclean();
    expect(fields, {
      "reason": "unclean",
      "age": 150,
      "version": "testing-2026-10-26g",
      "in_call": true,
      "screen_share": true,
      "camera": false,
    });
    expect(schema.validateEvent({"e": "exit_reason", "t": 10, ...fields!}),
        isTrue);
    crashed.markClean();
  });

  test("the heartbeat rewrites the marker on its own", () async {
    var calls = 0;
    final marker = SessionMarker(File("${dir.path}/session_marker.json"),
        version: "v",
        flags: () => SessionFlags(inCall: calls++ > 0),
        heartbeat: const Duration(milliseconds: 40));
    SessionFlags none() => const SessionFlags();
    final standard = SessionMarker(File("x"), version: "v", flags: none);
    expect(standard.heartbeat, const Duration(minutes: 1));
    marker.begin();
    await Future<void>.delayed(const Duration(milliseconds: 130));
    marker.markClean();
    expect(calls, greaterThanOrEqualTo(3));
    expect(jsonDecode(marker.file.readAsStringSync())["in_call"], isTrue);
  });

  test("ringing and ended calls don't count as in a call", () {
    final f = SessionFlags.fromCalls([
      _FakeSession(VoipState.incoming, isCameraEnabled: true),
      _FakeSession(VoipState.ended, isSharingScreen: true),
    ]);
    expect([f.inCall, f.screenShare, f.camera], [false, false, false]);
  });

  test("exitApp (quit, tray quit, update install) marks the session clean",
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel("plugins.flutter.io/path_provider"),
            (call) async => dir.path);
    final file = File("${dir.path}/session_marker.json");
    file.writeAsStringSync(jsonEncode({"state": "clean"}));

    await SessionMarkerTelemetry.start("testing-2026-10-26g");
    expect(jsonDecode(file.readAsStringSync())["state"], "running");

    await expectLater(
        exitApp(isWindows: false, exitProcess: (_) => throw _Exited()),
        throwsA(isA<_Exited>()));
    final m = jsonDecode(file.readAsStringSync());
    expect(m["state"], "clean");
    expect(m["version"], "testing-2026-10-26g");

    // The next launch reports nothing.
    expect(
        SessionMarker(file, version: "x", flags: () => const SessionFlags())
            .previousUnclean(),
        isNull);
    await SessionMarkerTelemetry.stop();
    expect(file.existsSync(), isFalse);
  });

  test(
      "joining a call, a screen share and the camera reach the marker at once "
      "(watcher attached after Telemetry.init, consent on later)", () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel("plugins.flutter.io/path_provider"),
            (call) async => dir.path);
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    final file = File("${dir.path}/session_marker.json");
    Map flags() => jsonDecode(file.readAsStringSync());

    // main.dart: ClientManager.init (and so the CallManager) comes after
    // Telemetry.init, and consent may be turned on later still.
    final calls = CallManager(_ClientManager())..playSounds = false;
    SessionMarkerTelemetry.watchCalls(calls);
    await SessionMarkerTelemetry.start("testing-2026-10-26g");
    expect(flags()["in_call"], isFalse);
    final written = flags()["beat"];

    // The heartbeat is a minute away; every change below has to be
    // written right away (the issue's "within a minute of a screen share").
    final session = _LiveSession();
    calls.currentSessions.add(session);
    await pumpEventQueue();
    expect([flags()["in_call"], flags()["screen_share"]], [true, false]);
    expect(flags()["beat"], greaterThanOrEqualTo(written));

    session.share(true);
    await pumpEventQueue();
    expect(flags()["screen_share"], isTrue);

    session.camera(true);
    await pumpEventQueue();
    expect(flags()["camera"], isTrue);

    session.share(false);
    await pumpEventQueue();
    expect([flags()["screen_share"], flags()["camera"]], [false, true]);

    // Leaving drops the call and its subscription.
    expect(SessionMarkerTelemetry.watchedSessions, 1);
    calls.currentSessions.remove(session);
    await pumpEventQueue();
    expect(SessionMarkerTelemetry.watchedSessions, 0);
    expect([flags()["in_call"], flags()["camera"]], [false, false]);

    await SessionMarkerTelemetry.stop();
  });
}
