// Vommet issue 1065 (telemetry schema v46): the real VoiceMessagePlayer
// watches the player opening a resolved voice message (path voice_open,
// step opening). media_kit's Player needs libmpv, so the player is the
// FakePlayer of telemetry_v45_test.dart, whose open() can hang like mpv
// stuck on the file.
// unit_test/ isn't a recognised test directory for the analyzer.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:io';

import 'package:commet/main.dart';
import 'package:commet/telemetry/media_load_telemetry.dart';
import 'package:commet/telemetry/telemetry_schema.dart';
import 'package:commet/telemetry/voice_message_telemetry.dart';
import 'package:commet/ui/molecules/voice_message/voice_message_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'telemetry_v45_test.dart' show FakePlayer, FakeFileProvider;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final schema = TelemetrySchema.parse(
      File("assets/telemetry/schema.json").readAsStringSync());
  final events = <Map<String, Object?>>[];
  late FakePlayer player;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });

  setUp(() {
    events.clear();
    player = FakePlayer();
    VoiceMessagePlayer.createPlayer = () => player;
    VoiceMessageTelemetry.enabled = () => false;
    MediaLoadWatch.stallAfter = const Duration(seconds: 10);
    MediaLoadWatch.enabled = () => true;
    MediaLoadWatch.record = (name, fields) {
      final ev = <String, Object?>{"e": name, "t": 1};
      fields.forEach((k, v) {
        if (v != null) ev[k] = v;
      });
      expect(schema.validateEvent(ev), isTrue,
          reason: "$name must fit the telemetry schema: $ev");
      events.add(ev);
    };
  });

  tearDown(() => MediaLoadWatch.enabled = () => false);

  Future<void> tapPlay(WidgetTester tester) async {
    final file = FakeFileProvider(Uri.file("/voice/v.ogg"));
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: VoiceMessagePlayer(file: file))));
    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pump();
    await tester.pump();
  }

  testWidgets("1065 a player that hangs opening records step opening",
      (tester) async {
    player.openHangs = true;
    await tapPlay(tester);
    await tester.pump(const Duration(seconds: 9));
    expect(events, isEmpty);
    await tester.pump(const Duration(seconds: 2));
    final stall = events.singleWhere((e) => e["e"] == "media_load_stall");
    expect(stall["path"], "voice_open");
    expect(stall["kind"], "voice");
    expect(stall["step"], "opening");
    expect(stall["encrypted"], false);
    expect(events.where((e) => e["e"] == "media_load"), isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  });

  testWidgets("1065 a player that opens records an ok end, no stall",
      (tester) async {
    await tapPlay(tester);
    final end = events.singleWhere((e) => e["e"] == "media_load");
    expect(end["path"], "voice_open");
    expect(end["step"], "opening");
    expect(end["outcome"], "ok");
    expect(end["stalled"], false);
    await tester.pump(const Duration(seconds: 11));
    expect(events.where((e) => e["e"] == "media_load_stall"), isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  });

  testWidgets("1065 a player whose open fails records an error end",
      (tester) async {
    player.openError = StateError("mpv failed");
    await tapPlay(tester);
    final end = events.singleWhere((e) => e["e"] == "media_load");
    expect(end["path"], "voice_open");
    expect(end["outcome"], "error");
    expect(end["error_type"], isNotNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  });
}
