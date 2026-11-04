// unit_test/ isn't a recognised test directory for the analyzer.
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:typed_data';

import 'package:commet/client/attachment.dart';
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
  bool canStart = true;
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
    if (!canStart) return false;
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
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    recorder = FakeVoiceRecorder();
    sent = [];
    MessageInputState.createVoiceRecorder = () => recorder;
  });

  tearDown(() => MessageInputState.debugPhoneOs = null);

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

  testWidgets("can't start without a Scaffold: the hint still shows",
      (tester) async {
    // The desktop chat layout has no Scaffold, so a SnackBar never appears
    // there (Vommet issue 558).
    recorder.canStart = false;
    await tester.pumpWidget(MaterialApp(
      home: Material(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: MessageInput(
            client: FakeClient(),
            availibleEmoticons: const [],
            onSendVoiceMessage: (recording, {overrideClient}) async => true,
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.mic));
    await tester.pump();
    expect(find.textContaining("microphone"), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    expect(find.textContaining("microphone"), findsNothing);
  });

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

  // Operator report 2026-11-03: on a phone a tap must not start recording.
  group("phone (hold to record)", () {
    setUp(() => MessageInputState.debugPhoneOs = true);

    testWidgets("tap on the mic: no recording, hold hint shows", (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final mic = await pumpComposer(tester);
      await tester.tapAt(mic);
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        recorder.recording,
        isFalse,
        reason: "a tap must not start recording on a phone",
      );
      expect(
        find.text("Hold the microphone to record, release to send."),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets("send a picture, tap the mic that replaced Send: no recording",
        (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var attachments = [
        PendingFileAttachment(
            name: "photo.png",
            data: Uint8List(0),
            mimeType: "application/octet-stream"),
      ];
      var sends = 0;
      late StateSetter setOuter;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: StatefulBuilder(
                builder: (context, setState) {
                  setOuter = setState;
                  return MessageInput(
                    client: FakeClient(),
                    availibleEmoticons: const [],
                    attachments: attachments,
                    onSendMessage: (message, {overrideClient}) {
                      sends++;
                      setOuter(() => attachments = []);
                      return MessageInputSendResult.success;
                    },
                    onSendVoiceMessage: (recording, {overrideClient}) async {
                      sent.add(recording);
                      return true;
                    },
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byIcon(Icons.mic), findsNothing);
      final send = tester.getCenter(
        find.byKey(const ValueKey("composer-send")),
      );
      await tester.tapAt(send);
      await tester.pump(const Duration(milliseconds: 100));
      expect(sends, 1);
      expect(
        find.byIcon(Icons.mic),
        findsOneWidget,
        reason: "the send button turns back into the mic",
      );
      // the accidental second tap, on the button that was Send (the
      // composer shrinks once the attachment strip is gone)
      await tester.tapAt(tester.getCenter(find.byIcon(Icons.mic)));
      await tester.pump(const Duration(milliseconds: 100));
      expect(recorder.recording, isFalse);
      expect(find.text("Slide to cancel"), findsNothing);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets("hold, release: sends", (tester) async {
      final mic = await pumpComposer(tester);
      final gesture = await holdMic(tester, mic);
      expect(find.byKey(const ValueKey("voice-lock-hint")), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 100));
      expect(sent, hasLength(1));
      expect(recorder.recording, isFalse);
      // no stray tap fires after the long press ends
      await tester.pump(const Duration(seconds: 1));
      expect(recorder.recording, isFalse);
      expect(
        find.text("Hold the microphone to record, release to send."),
        findsNothing,
      );
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets(
        "hold, slide up: locks hands-free; release keeps recording, "
        "tap sends", (tester) async {
      final mic = await pumpComposer(tester);
      final gesture = await holdMic(tester, mic);
      for (var i = 0; i < 6; i++) {
        await gesture.moveBy(const Offset(0, -16));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 100));
      expect(sent, isEmpty, reason: "release after locking must not send");
      expect(recorder.recording, isTrue);
      expect(find.byIcon(Icons.send), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
      expect(find.text("Slide to cancel"), findsNothing);
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.byIcon(Icons.send));
      await tester.pump(const Duration(milliseconds: 100));
      expect(sent, hasLength(1));
      expect(recorder.recording, isFalse);
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets("hold, slide left: cancels", (tester) async {
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
  });

  testWidgets("desktop: tap starts hands-free recording", (tester) async {
    MessageInputState.debugPhoneOs = false;
    final mic = await pumpComposer(tester);
    await tester.tapAt(mic);
    await tester.pump(const Duration(milliseconds: 100));
    expect(recorder.recording, isTrue);
    expect(find.byIcon(Icons.send), findsOneWidget);
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump(const Duration(milliseconds: 100));
    expect(sent, hasLength(1));
    await tester.pump(const Duration(seconds: 10));
  });
}
