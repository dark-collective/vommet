// Vommet: voice message round trip on the desktop build, no homeserver
// needed. A reporter (11-04, Linux Flatpak) found voice messages broken on PC
// while they worked on the phone; the unit tests only ever used a fake
// recorder and no player, so nothing ran the desktop path. This test does:
//
//  1. the real VoiceRecorder (record_linux: parecord -> ffmpeg) records the
//     fed virtual microphone and must return a real Ogg/Opus file with the
//     fed signal in its waveform;
//  2. the real desktop composer: tap the mic, wait, tap send; the recording
//     must reach onSendVoiceMessage;
//  3. the real VoiceMessagePlayer must load and play what was recorded, and
//     the phone formats (Ogg/Opus from Android, AAC/MP4 from iOS/Windows)
//     from VOICE_FIXTURES.
//
// Runs only with --dart-define=CAPTURE_TEST=true (it needs a fed virtual
// microphone: .vommet/it/capture-linux.sh).

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:commet/cache/file_provider.dart';
import 'package:commet/client/client.dart';
import 'package:commet/ui/molecules/message_input.dart';
import 'package:commet/ui/molecules/voice_message/voice_message_player.dart';
import 'package:commet/utils/voice_message.dart';
import 'package:commet/utils/voice_recorder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';

const _enabled = bool.fromEnvironment('CAPTURE_TEST');

/// Directory with phone-format voice files made by the harness
/// (voice.ogg = Android, voice.m4a = iOS/Windows).
const _fixtures = String.fromEnvironment('VOICE_FIXTURES');

void voiceLog(String line) {
  // ignore: avoid_print
  print("CAPTURE voice: $line");
}

class _FakeClient implements Client {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FileUri implements FileProvider {
  _FileUri(this.file);
  final File file;

  @override
  Future<Uri?> resolve() async => file.uri;
  @override
  Future<Uint8List?> getFileData() => file.readAsBytes();
  @override
  Future<void> save(String filepath) => file.copy(filepath);
  @override
  Stream<DownloadProgress>? get onProgressChanged => null;
  @override
  String get fileIdentifier => file.path;
}

bool _contains(Uint8List bytes, String marker) {
  final m = ascii.encode(marker);
  outer:
  for (var i = 0; i + m.length <= bytes.length; i++) {
    for (var j = 0; j < m.length; j++) {
      if (bytes[i + j] != m[j]) continue outer;
    }
    return true;
  }
  return false;
}

/// Why [r] isn't a usable voice message of about [atLeast], or null.
String? _checkRecording(VoiceRecording? r, Duration atLeast) {
  if (r == null) return "the recorder returned nothing";
  voiceLog("recorded ${r.bytes.length} bytes, ${r.duration.inMilliseconds} ms, "
      "${r.format.name}, waveform max ${r.waveform.fold<int>(0, (a, b) => a > b ? a : b)}");
  if (r.duration < atLeast) return "duration ${r.duration} < $atLeast";
  if (r.bytes.length < 2000) return "only ${r.bytes.length} bytes";
  if (Platform.isLinux) {
    if (r.format != VoiceFormat.oggOpus) return "Linux recorded ${r.format}";
    if (!_contains(Uint8List.sublistView(r.bytes, 0, 4), "OggS")) {
      return "not an Ogg file";
    }
    if (!_contains(r.bytes, "OpusHead")) return "no Opus stream in the Ogg";
  }
  // The harness feeds a loud warble: the waveform must show it (a silent
  // or unread microphone leaves every bar near zero).
  final loud = r.waveform.where((v) => v > VoiceMessage.waveformMax / 4);
  if (loud.length < r.waveform.length ~/ 4) {
    return "the waveform is silent (${loud.length}/${r.waveform.length} loud bars)";
  }
  return null;
}

Future<void> _wait(WidgetTester tester, Duration d) async {
  await tester.runAsync(() => Future<void>.delayed(d));
  await tester.pump();
}

/// Plays [file] in the real VoiceMessagePlayer: the play button must load
/// it, the duration must come from the media and the position must move.
Future<void> _expectPlays(WidgetTester tester, File file, String what) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
            width: 400, child: VoiceMessagePlayer(file: _FileUri(file))),
      ),
    ),
  ));
  await tester.pump();
  await tester.tap(find.byIcon(Icons.play_arrow));
  final state = tester.state(find.byType(VoiceMessagePlayer)) as dynamic;
  Duration? total;
  var position = Duration.zero;
  for (var i = 0; i < 50; i++) {
    await _wait(tester, const Duration(milliseconds: 100));
    total = state.mediaDuration as Duration?;
    position = state.position as Duration;
    if (state.failed == true) break;
    if (position > const Duration(milliseconds: 800)) break;
  }
  voiceLog("$what: failed=${state.failed} duration=$total position=$position");
  expect(state.failed, isFalse, reason: "$what: the player couldn't load it");
  expect(total, isNotNull, reason: "$what: no duration from the media");
  expect(total! > const Duration(milliseconds: 500), isTrue,
      reason: "$what: duration $total");
  expect(position > const Duration(milliseconds: 800), isTrue,
      reason: "$what: playback didn't advance (position $position)");
  await tester.pumpWidget(const SizedBox());
  await _wait(tester, const Duration(milliseconds: 300));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  VoiceRecording? recorded;

  testWidgets('recorder: the fed microphone becomes a voice file',
      (tester) async {
    final recorder = VoiceRecorder();
    final started = await tester.runAsync(recorder.start);
    expect(started, isTrue, reason: "VoiceRecorder.start() failed");
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(seconds: 3)));
    final r = await tester.runAsync(recorder.stop);
    await tester.runAsync(recorder.dispose);
    final failure = _checkRecording(r, const Duration(milliseconds: 2500));
    expect(failure, isNull, reason: failure);
    recorded = r;
  }, skip: !_enabled);

  testWidgets('desktop composer: tap the mic, tap send, it is sent',
      (tester) async {
    final sent = <VoiceRecording>[];
    MessageInputState.debugPhoneOs = false;
    addTearDown(() => MessageInputState.debugPhoneOs = null);
    await tester.pumpWidget(MaterialApp(
      home: Material(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: MessageInput(
            client: _FakeClient(),
            availibleEmoticons: const [],
            onSendVoiceMessage: (recording, {overrideClient}) async {
              sent.add(recording);
              return true;
            },
          ),
        ),
      ),
    ));
    await tester.pump();
    expect(find.byIcon(Icons.mic), findsOneWidget,
        reason: "no mic button in the desktop composer");
    await tester.tap(find.byIcon(Icons.mic));
    // start() spawns parecord + ffmpeg: give it real time.
    for (var i = 0; i < 20 && find.byIcon(Icons.send).evaluate().isEmpty; i++) {
      await _wait(tester, const Duration(milliseconds: 100));
    }
    expect(find.byIcon(Icons.send), findsOneWidget,
        reason: "tapping the mic didn't start recording "
            "(hint shown: ${find.byType(Text).evaluate().map((e) => (e.widget as Text).data).whereType<String>().join(' | ')})");
    await _wait(tester, const Duration(seconds: 3));
    await tester.tap(find.byIcon(Icons.send));
    for (var i = 0; i < 50 && sent.isEmpty; i++) {
      await _wait(tester, const Duration(milliseconds: 100));
    }
    expect(sent, hasLength(1), reason: "the recording was never sent");
    final failure = _checkRecording(sent.single, const Duration(seconds: 2));
    expect(failure, isNull, reason: failure);
    await _wait(tester, const Duration(seconds: 1));
  }, skip: !_enabled);

  testWidgets('player: our own recording plays', (tester) async {
    expect(recorded, isNotNull, reason: "the recorder test didn't record");
    final dir = await Directory.systemTemp.createTemp("vommet-voice");
    addTearDown(() => dir.delete(recursive: true));
    final file = File("${dir.path}/own.${recorded!.format.extension}");
    await file.writeAsBytes(recorded!.bytes);
    await _expectPlays(tester, file, "own recording");
  }, skip: !_enabled);

  for (final name in ["voice.ogg", "voice.m4a"]) {
    testWidgets('player: a phone voice message ($name) plays', (tester) async {
      final file = File("$_fixtures/$name");
      expect(file.existsSync(), isTrue, reason: "missing fixture $file");
      await _expectPlays(tester, file, name);
    }, skip: !_enabled || _fixtures.isEmpty);
  }

  // The harness requires this line, so a skipped run can't pass.
  testWidgets('voice messages: all checks ran', (tester) async {
    // ignore: avoid_print
    print("CAPTURE VOICE PASS");
  }, skip: !_enabled);
}
