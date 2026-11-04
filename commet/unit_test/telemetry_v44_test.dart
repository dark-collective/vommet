// Vommet telemetry schema v44: the microphone at call join (call_mic) and
// how many tiles the call view is offered (call_stats tiles_shown). Report
// 2026-11-04: a 1:1 call alone sent no audio, with no error logged.

import 'dart:io';

import 'package:commet/main.dart';
import 'package:commet/telemetry/call_mic_telemetry.dart';
import 'package:commet/telemetry/call_stats.dart';
import 'package:commet/telemetry/telemetry_schema.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final schema = TelemetrySchema.parse(
      File("assets/telemetry/schema.json").readAsStringSync());
  bool valid(Map<String, Object?> fields) =>
      schema.validateEvent({"e": "call_mic", "t": 1, ...fields});
  Future<MicrophoneChoice?> usbMissing() async =>
      (choice: "preferred_missing", label: "USB Audio Device", devices: 2);

  setUpAll(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });

  test("schema is v44 with call_mic", () {
    expect(schema.version, greaterThanOrEqualTo(44));
    expect(schema.hasEvent("call_mic"), isTrue);
  });

  test("a microphone that starts: outcome ok with the capture device fields",
      () async {
    final fields = await CallMicTelemetry.measure(Future.value(),
        mode: "open", microphone: usbMissing);
    expect(fields, {
      "kind": "matrixrtc",
      "mode": "open",
      "ms": fields["ms"],
      "device_choice": "preferred_missing",
      "device_type": "usb",
      "devices": 2,
      "outcome": "ok",
    });
    expect(valid(fields), isTrue);
  });

  test(
      "a platform error is caught, recorded with a capture error kind, "
      "never its message", () async {
    final fields = await CallMicTelemetry.measure(
        Future.error(PlatformException(
            code: "getUserMedia",
            message: "NotAllowedError: Permission denied by the system")),
        mode: "muted");
    expect(fields["outcome"], "error");
    expect(fields["error_kind"], "permission");
    expect(fields["error_type"], "PlatformException");
    expect(fields.values.join(" "), isNot(contains("denied")));
    expect(fields.containsKey("devices"), isFalse);
    expect(valid(fields), isTrue);
  });

  test("no local participant counts as a failure", () async {
    final fields = await CallMicTelemetry.measure(null,
        mode: "push_to_talk",
        microphone: () async => throw StateError("enumerate"));
    expect(fields["outcome"], "error");
    expect(valid(fields), isTrue);
  });

  test("call_stats carries tiles_shown, 0 included", () {
    final fields = (CallSample()..tilesShown = 0).fields();
    expect(fields["tiles_shown"], 0);
    expect(
        schema.validateEvent(
            {"e": "call_stats", "t": 1, "quality": "good", ...fields}),
        isTrue);
    expect(CallSample().fields().containsKey("tiles_shown"), isFalse);
  });

  group("track", () {
    final recorded = <Map<String, Object?>>[];
    var asked = 0;
    setUp(() {
      recorded.clear();
      asked = 0;
      CallMicTelemetry.record = (e, f) => recorded.add({"e": e, ...f});
      CallMicTelemetry.microphone = () async {
        asked++;
        return (choice: "default", label: "Built-in Audio", devices: 1);
      };
    });
    tearDown(() => CallMicTelemetry.enabled = () => false);

    test("telemetry off: nothing recorded, devices never read", () async {
      CallMicTelemetry.enabled = () => false;
      await CallMicTelemetry.track(Future.error(StateError("mic")),
          mode: "open");
      expect(recorded, isEmpty);
      expect(asked, 0);
    });

    test("telemetry on: one call_mic with the outcome and devices", () async {
      CallMicTelemetry.enabled = () => true;
      await CallMicTelemetry.track(Future.value(), mode: "push_to_talk");
      expect(recorded, hasLength(1));
      final ev = recorded.single;
      expect(ev["e"], "call_mic");
      expect(ev["mode"], "push_to_talk");
      expect(ev["outcome"], "ok");
      expect(ev["device_choice"], "default");
      expect(ev["device_type"], "builtin");
      expect(asked, 1);
      expect(schema.validateEvent({"t": 1, ...ev}), isTrue);
    });
  });

  group("startAtJoin", () {
    final recorded = <Map<String, Object?>>[];
    final calls = <String>[];
    setUp(() {
      recorded.clear();
      calls.clear();
      CallMicTelemetry.enabled = () => true;
      CallMicTelemetry.record = (e, f) => recorded.add({"e": e, ...f});
      CallMicTelemetry.microphone =
          () async => (choice: "default", label: "Built-in Audio", devices: 1);
    });
    tearDown(() => CallMicTelemetry.enabled = () => false);

    // A local participant: what the join asked of it.
    Future<void> publishMuted() async => calls.add("publishMuted");
    Future<void> setEnabled(bool on) async => calls.add("setEnabled($on)");

    Future<Map<String, Object?>> join(
        {required bool pushToTalk,
        required bool muted,
        bool participant = true}) async {
      final start = CallMicTelemetry.startAtJoin(
          pushToTalk: pushToTalk,
          muted: muted,
          publishMuted: participant ? publishMuted : null,
          setEnabled: participant ? setEnabled : null);
      expect(start == null, !participant);
      await pumpEventQueue();
      expect(recorded, hasLength(1));
      expect(schema.validateEvent({"t": 1, ...recorded.single}), isTrue);
      return recorded.single;
    }

    test("open: the microphone is enabled", () async {
      final ev = await join(pushToTalk: false, muted: false);
      expect(calls, ["setEnabled(true)"]);
      expect((ev["mode"], ev["outcome"]), ("open", "ok"));
    });

    test("started muted: published disabled, mode muted", () async {
      final ev = await join(pushToTalk: false, muted: true);
      expect(calls, ["setEnabled(false)"]);
      expect((ev["mode"], ev["outcome"]), ("muted", "ok"));
    });

    test("push to talk: published muted, capture open", () async {
      final ev = await join(pushToTalk: true, muted: false);
      expect(calls, ["publishMuted"]);
      expect((ev["mode"], ev["outcome"]), ("push_to_talk", "ok"));
    });

    test("push to talk, started muted: nothing published", () async {
      final ev = await join(pushToTalk: true, muted: true);
      expect(calls, isEmpty);
      expect((ev["mode"], ev["outcome"]), ("muted", "ok"));
    });

    test("no local participant: recorded as an error, no crash", () async {
      for (final ptt in [false, true]) {
        recorded.clear();
        final ev =
            await join(pushToTalk: ptt, muted: false, participant: false);
        expect(calls, isEmpty);
        expect(ev["outcome"], "error");
      }
    });

    test("a start that throws: recorded as an error with its kind", () async {
      final start = CallMicTelemetry.startAtJoin(
          pushToTalk: false,
          muted: false,
          publishMuted: null,
          setEnabled: (_) async => throw StateError("no device"));
      await expectLater(start, throwsStateError);
      await pumpEventQueue();
      expect(recorded.single["outcome"], "error");
      expect(recorded.single["error_type"], isNotNull);
    });
  });

  test("mode: muted wins over push to talk, every mode is in the schema",
      () async {
    final modes = {
      for (final ptt in [false, true])
        for (final muted in [false, true])
          (ptt, muted): CallMicTelemetry.modeFor(pushToTalk: ptt, muted: muted),
    };
    expect(modes, {
      (false, false): "open",
      (false, true): "muted",
      (true, false): "push_to_talk",
      (true, true): "muted",
    });
    for (final mode in modes.values) {
      expect(valid(await CallMicTelemetry.measure(Future.value(), mode: mode)),
          isTrue);
    }
  });
}
