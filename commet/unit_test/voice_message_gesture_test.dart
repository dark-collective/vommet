import 'dart:typed_data';

import 'package:commet/client/client.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/molecules/message_input.dart';
import 'package:commet/utils/voice_message.dart';
import 'package:commet/utils/voice_recorder.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeClient implements Client {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class FakeVoiceRecorder implements VoiceRecorder {
  bool recording = false;
  int cancels = 0;
  final Stopwatch clock = Stopwatch();

  @override
  Stream<double> get levels => const Stream.empty();
  @override
  Duration get elapsed => clock.elapsed;
  @override
  bool get isRecording => recording;

  @override
  Future<bool> start() async {
    recording = true;
    clock
      ..reset()
      ..start();
    return true;
  }

  @override
  Future<VoiceRecording?> stop() async {
    recording = false;
    return VoiceRecording(
        bytes: Uint8List(8),
        format: VoiceFormat.oggOpus,
        duration: const Duration(seconds: 2),
        waveform: const [0, 512, 1024]);
  }

  @override
  Future<void> cancel() async {
    recording = false;
    cancels++;
  }

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  late FakeVoiceRecorder recorder;
  late List<VoiceRecording> sent;

  setUp(() async {
    // unit_test/ isn't a recognised test directory for the analyzer.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    recorder = FakeVoiceRecorder();
    sent = [];
    MessageInputState.createVoiceRecorder = () => recorder;
  });

  Future<Offset> pumpComposer(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: MessageInput(
            client: FakeClient(),
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
    return tester.getCenter(find.byIcon(Icons.mic));
  }

  Future<TestGesture> holdMic(WidgetTester tester, Offset mic) async {
    final gesture = await tester.startGesture(mic);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(recorder.recording, isTrue, reason: "long press starts recording");
    return gesture;
  }

  testWidgets("hold, release: sends the voice message", (tester) async {
    final mic = await pumpComposer(tester);
    final gesture = await holdMic(tester, mic);
    await tester.pump(const Duration(seconds: 1));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 100));
    expect(sent, hasLength(1));
    expect(recorder.recording, isFalse);
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets("hold, slide left: cancels without sending", (tester) async {
    final mic = await pumpComposer(tester);
    final gesture = await holdMic(tester, mic);
    for (var i = 0; i < 6; i++) {
      await gesture.moveBy(const Offset(-25, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(recorder.cancels, 1);
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 100));
    expect(sent, isEmpty);
    await tester.pump(const Duration(seconds: 10));
  });
}
