// Vommet telemetry schema v45: voice messages (voice_message). Report
// 2026-11-04: a tester's voice messages didn't play on desktop, and nothing
// showed whether recording, sending or playing failed.
// unit_test/ isn't a recognised test directory for the analyzer.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:commet/cache/file_provider.dart';
import 'package:commet/client/client.dart';
import 'package:commet/main.dart';
import 'package:commet/telemetry/telemetry_schema.dart';
import 'package:commet/telemetry/voice_message_telemetry.dart';
import 'package:commet/ui/molecules/message_input.dart';
import 'package:commet/ui/molecules/voice_message/voice_message_player.dart';
import 'package:commet/utils/voice_message.dart';
import 'package:commet/utils/voice_recorder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeClient implements Client {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// The recorder's boundary (the record plugin): start can fail, stop returns
/// what was recorded.
class FakeVoiceRecorder implements VoiceRecorder {
  bool recording = false;
  String? failWith;
  VoiceRecording? result;

  @override
  String? startFailure;
  @override
  Stream<double> get levels => const Stream.empty();
  @override
  Duration get elapsed => const Duration(seconds: 2);
  @override
  bool get isRecording => recording;

  @override
  Future<bool> start() async {
    startFailure = failWith;
    if (failWith != null) return false;
    recording = true;
    return true;
  }

  @override
  Future<VoiceRecording?> stop() async {
    recording = false;
    return result;
  }

  @override
  Future<void> cancel() async => recording = false;

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// media_kit's Player needs libmpv; this one models its streams.
class FakePlayer implements Player {
  final playingC = StreamController<bool>.broadcast();
  final positionC = StreamController<Duration>.broadcast();
  final durationC = StreamController<Duration>.broadcast();
  final completedC = StreamController<bool>.broadcast();
  Object? openError;
  Object? playError;

  /// open() never finishes (libmpv stuck on the file).
  bool openHangs = false;

  /// Whether the position moves after play(). Like media_kit (`playing`
  /// mirrors mpv's `pause` property, media_kit
  /// 1.2.6 lib/src/player/native/player/real.dart:1507), play() always reports
  /// playing = true; only the position shows that audio actually runs.
  bool advances = true;

  @override
  late final PlayerStream stream = PlayerStream(
    const Stream.empty(),
    playingC.stream,
    completedC.stream,
    positionC.stream,
    durationC.stream,
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
  );

  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    if (openError != null) throw openError!;
    if (openHangs) return Completer<void>().future;
    durationC.add(const Duration(milliseconds: 2300));
  }

  @override
  Future<void> setPlaylistMode(PlaylistMode playlistMode) async {}
  @override
  Future<void> setRate(double rate) async {}
  @override
  Future<void> play() async {
    if (playError != null) throw playError!;
    playingC.add(true);
    if (advances) positionC.add(const Duration(milliseconds: 40));
  }

  @override
  Future<void> pause() async => playingC.add(false);
  @override
  Future<void> seek(Duration duration) async {}
  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// A file provider that resolves to [uri] (null: the download failed).
class FakeFileProvider implements FileProvider {
  FakeFileProvider([this.uri, this.hangs = false]);
  final Uri? uri;

  /// resolve() never finishes (e.g. the media cache never answers).
  final bool hangs;

  @override
  Future<Uri?> resolve() =>
      hangs ? Completer<Uri?>().future : Future.value(uri);
  @override
  String get fileIdentifier => "voice";
  @override
  Stream<DownloadProgress>? get onProgressChanged => null;
  @override
  Future<Uint8List?> getFileData() async => null;
  @override
  Future<void> save(String filepath) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final schema = TelemetrySchema.parse(
      File("assets/telemetry/schema.json").readAsStringSync());
  bool valid(Map<String, Object?> fields) => schema.validateEvent({
        "e": "voice_message",
        "t": 1,
        for (final e in fields.entries)
          if (e.value != null) e.key: e.value,
      });
  final recorded = <Map<String, Object?>>[];
  final recording = VoiceRecording(
      bytes: Uint8List(1200),
      format: VoiceFormat.oggOpus,
      duration: const Duration(seconds: 3),
      waveform: const [0, 300, 700, 120]);

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });

  setUp(() {
    recorded.clear();
    VoiceMessageTelemetry.enabled = () => true;
    VoiceMessageTelemetry.record = (e, f) => recorded.add({"e": e, ...f});
  });
  tearDown(() => VoiceMessageTelemetry.enabled = () => false);

  test("schema is v45 with voice_message", () {
    expect(schema.version, greaterThanOrEqualTo(45));
    expect(schema.hasEvent("voice_message"), isTrue);
  });

  group("field builders", () {
    test("record: every outcome and reason validates", () {
      final cases = [
        VoiceMessageTelemetry.recordFields(
            hold: true, outcome: "ok", startMs: 40, recording: recording),
        for (final reason in ["no_permission", "start_failed"])
          VoiceMessageTelemetry.recordFields(
              hold: false, outcome: "error", reason: reason, startMs: 5),
        VoiceMessageTelemetry.recordFields(
            hold: true,
            outcome: "error",
            reason: "nothing_recorded",
            elapsed: const Duration(seconds: 1)),
        VoiceMessageTelemetry.recordFields(
            hold: true,
            outcome: "error",
            reason: "too_short",
            recording: recording),
        VoiceMessageTelemetry.recordFields(
            hold: false,
            outcome: "cancelled",
            reason: "cancelled",
            elapsed: const Duration(seconds: 4)),
      ];
      for (final f in cases) {
        expect(valid(f), isTrue, reason: "$f");
      }
      expect(cases.first, {
        "op": "record",
        "outcome": "ok",
        "mode": "hold",
        "start_ms": 40,
        "duration_ms": 3000,
        "bytes": 1200,
        "format": "ogg_opus",
        "level_peak": 700,
      });
    });

    test("record: a silent microphone has level_peak 0", () {
      final f = VoiceMessageTelemetry.recordFields(
          hold: false,
          outcome: "ok",
          recording: VoiceRecording(
              bytes: Uint8List(10),
              format: VoiceFormat.aacMp4,
              duration: const Duration(seconds: 2),
              waveform: const [0, 0]));
      expect(f["level_peak"], 0);
      expect(f["format"], "aac_mp4");
      expect(valid(f), isTrue);
    });

    test("send: ok, failure with the error fields, no room", () {
      final ok = VoiceMessageTelemetry.sendFields(
          ms: 300, bytes: 1200, encrypted: true);
      expect(ok, {
        "op": "send",
        "ms": 300,
        "bytes": 1200,
        "encrypted": true,
        "outcome": "ok",
      });
      final failed = VoiceMessageTelemetry.sendFields(
          ms: 300,
          bytes: 1200,
          encrypted: false,
          error: matrix.MatrixException.fromJson(
              {"errcode": "M_FORBIDDEN", "error": "secret room text"}));
      expect(failed["outcome"], "error");
      expect(failed["reason"], "send_failed");
      expect(failed["errcode"], "M_FORBIDDEN");
      expect(failed.values.join(" "), isNot(contains("secret")));
      final noRoom =
          VoiceMessageTelemetry.sendFields(ms: 0, bytes: 1, noRoom: true);
      expect(noRoom["reason"], "no_room");
      for (final f in [ok, failed, noRoom]) {
        expect(valid(f), isTrue, reason: "$f");
      }
    });

    test("play: every reason validates, mime parameters are stripped", () {
      expect(VoiceMessageTelemetry.mime("audio/ogg; codecs=opus"), "audio/ogg");
      expect(VoiceMessageTelemetry.mime("not a mime"), isNull);
      final a =
          VoicePlayAttempt(retry: true, encrypted: true, mime: "audio/ogg")
            ..resolved()
            ..opened();
      for (final reason in [
        "resolve_failed",
        "open_failed",
        "resolve_stalled",
        "open_stalled",
        "no_start",
        "play_failed"
      ]) {
        final f = a.fields(
            outcome: "error",
            reason: reason,
            media: const Duration(seconds: 2),
            error: StateError("x"));
        expect(f["error_type"], "StateError");
        expect(valid(f), isTrue, reason: "$f");
      }
      expect(valid(a.fields(outcome: "ok", startMs: 30)), isTrue);
      a.dispose();
    });

    test("telemetry off: nothing recorded, no play attempt", () {
      VoiceMessageTelemetry.enabled = () => false;
      VoiceMessageTelemetry.recorded(hold: true, outcome: "ok");
      VoiceMessageTelemetry.sent(ms: 1, bytes: 1);
      expect(VoiceMessageTelemetry.startPlay(FakeFileProvider(), retry: false),
          isNull);
      expect(recorded, isEmpty);
    });
  });

  group("MessageInput records op=record", () {
    late FakeVoiceRecorder recorder;
    late List<VoiceRecording> sent;

    setUp(() {
      recorder = FakeVoiceRecorder()..result = recording;
      sent = [];
      MessageInputState.createVoiceRecorder = () => recorder;
    });

    Future<MessageInputState> pump(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: MessageInput(
              client: FakeClient(),
              availibleEmoticons: const [],
              onSendVoiceMessage: (r, {overrideClient}) async {
                sent.add(r);
                return true;
              },
            ),
          ),
        ),
      ));
      await tester.pump();
      return tester.state<MessageInputState>(find.byType(MessageInput));
    }

    Future<void> settle(WidgetTester tester) =>
        tester.pump(const Duration(seconds: 5));

    List<Map<String, Object?>> events() =>
        recorded.where((e) => e["op"] == "record").toList();

    testWidgets("sent: one ok with duration, size, format and peak",
        (tester) async {
      final state = await pump(tester);
      await state.startVoiceRecording(hold: false);
      await state.finishVoiceRecording();
      await settle(tester);
      expect(sent, hasLength(1));
      expect(events(), hasLength(1));
      final e = events().single;
      expect(e["outcome"], "ok");
      expect(e["mode"], "tap");
      expect(e["duration_ms"], 3000);
      expect(e["bytes"], 1200);
      expect(e["level_peak"], 700);
      expect(valid(e..remove("e")), isTrue);
    });

    testWidgets("no permission: one no_permission", (tester) async {
      recorder.failWith = "no_permission";
      final state = await pump(tester);
      await state.startVoiceRecording(hold: true);
      await settle(tester);
      expect(events(), hasLength(1));
      expect(events().single["reason"], "no_permission");
      expect(events().single["outcome"], "error");
    });

    testWidgets("too short: one too_short, nothing sent", (tester) async {
      recorder.result = VoiceRecording(
          bytes: Uint8List(50),
          format: VoiceFormat.oggOpus,
          duration: const Duration(milliseconds: 200),
          waveform: const [10]);
      final state = await pump(tester);
      await state.startVoiceRecording(hold: true);
      await state.finishVoiceRecording();
      await settle(tester);
      expect(sent, isEmpty);
      expect(events(), hasLength(1));
      expect(events().single["reason"], "too_short");
    });

    testWidgets("nothing recorded: one nothing_recorded", (tester) async {
      recorder.result = null;
      final state = await pump(tester);
      await state.startVoiceRecording(hold: false);
      await state.finishVoiceRecording();
      await settle(tester);
      expect(events(), hasLength(1));
      expect(events().single["reason"], "nothing_recorded");
    });

    testWidgets("canceled: one cancelled, nothing sent", (tester) async {
      final state = await pump(tester);
      await state.startVoiceRecording(hold: true);
      await state.cancelVoiceRecording();
      await settle(tester);
      expect(sent, isEmpty);
      expect(events(), hasLength(1));
      expect(events().single["outcome"], "cancelled");
      expect(events().single["mode"], "hold");
    });
  });

  group("VoiceMessagePlayer records op=play", () {
    late FakePlayer player;
    setUp(() {
      player = FakePlayer();
      VoiceMessagePlayer.createPlayer = () => player;
    });

    Future<void> pumpPlayer(WidgetTester tester, FileProvider file) async {
      await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: VoiceMessagePlayer(file: file))));
      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pump();
    }

    testWidgets("resolve() null: one resolve_failed, retry on the next tap",
        (tester) async {
      await pumpPlayer(tester, FakeFileProvider());
      await tester.pump();
      expect(recorded, hasLength(1));
      final e = recorded.single;
      expect(e["op"], "play");
      expect(e["outcome"], "error");
      expect(e["reason"], "resolve_failed");
      expect(e["retry"], isFalse);
      expect(valid(e..remove("e")), isTrue);

      await tester.tap(find.byIcon(Icons.error_outline));
      await tester.pump();
      await tester.pump();
      expect(recorded, hasLength(2));
      expect(recorded.last["retry"], isTrue);
    });

    testWidgets("resolve() never finishes: one resolve_stalled after 15 s",
        (tester) async {
      await pumpPlayer(tester, FakeFileProvider(null, true));
      await tester.pump(const Duration(seconds: 14));
      expect(recorded, isEmpty);
      await tester.pump(const Duration(seconds: 2));
      expect(recorded, hasLength(1));
      final e = recorded.single;
      expect(e["outcome"], "error");
      expect(e["reason"], "resolve_stalled");
      expect(e.containsKey("resolve_ms"), isFalse);
      expect(valid(e..remove("e")), isTrue);
    });

    testWidgets("disposed while loading: nothing, no timer left",
        (tester) async {
      await pumpPlayer(tester, FakeFileProvider(null, true));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 30));
      expect(recorded, isEmpty);
    });

    group("with a file", () {
      final file = FakeFileProvider(Uri.file("/voice/v.ogg"));

      testWidgets("plays: one ok with the media duration", (tester) async {
        await pumpPlayer(tester, file);
        await tester.pump();
        await tester.pump();
        expect(recorded, hasLength(1));
        final e = recorded.single;
        expect(e["outcome"], "ok", reason: "$e");
        expect(e["media_ms"], 2300);
        expect(valid(e..remove("e")), isTrue);
        await tester.pump(const Duration(seconds: 6));
        expect(recorded, hasLength(1), reason: "no second event");
      });

      testWidgets("open throws: one open_failed with its type", (tester) async {
        player.openError = StateError("cannot open /secret/path");
        await pumpPlayer(tester, file);
        await tester.pump();
        expect(recorded, hasLength(1));
        expect(recorded.single["reason"], "open_failed");
        expect(recorded.single["error_type"], "StateError");
        expect(recorded.single.values.join(" "), isNot(contains("secret")));
      });

      testWidgets("open never finishes: one open_stalled after 15 s",
          (tester) async {
        player.openHangs = true;
        await pumpPlayer(tester, file);
        await tester.pump(const Duration(seconds: 14));
        expect(recorded, isEmpty);
        await tester.pump(const Duration(seconds: 2));
        expect(recorded, hasLength(1));
        final e = recorded.single;
        expect(e["reason"], "open_stalled");
        expect(e["resolve_ms"], isNotNull);
        expect(e.containsKey("open_ms"), isFalse);
        expect(valid(e..remove("e")), isTrue);
        await tester.pump(const Duration(seconds: 30));
        expect(recorded, hasLength(1), reason: "no second event");
      });

      testWidgets("playing alone is not ok; the first position is",
          (tester) async {
        player.advances = false;
        await pumpPlayer(tester, file);
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        expect(recorded, isEmpty, reason: "playing=true without progress");
        player.positionC.add(const Duration(milliseconds: 40));
        await tester.pump();
        expect(recorded, hasLength(1));
        expect(recorded.single["outcome"], "ok");
        expect(recorded.single["start_ms"], isA<int>());
        await tester.pump(const Duration(seconds: 6));
        expect(recorded, hasLength(1), reason: "no late no_start");
      });

      testWidgets("never starts: one no_start after 5 s", (tester) async {
        player.advances = false;
        await pumpPlayer(tester, file);
        await tester.pump();
        expect(recorded, isEmpty);
        await tester.pump(const Duration(seconds: 6));
        expect(recorded, hasLength(1));
        expect(recorded.single["reason"], "no_start");
        expect(recorded.single["media_ms"], 2300);
      });
    });
  });
}
