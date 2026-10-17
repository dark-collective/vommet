import 'dart:async';
import 'dart:io';

import 'package:commet/cache/file_provider.dart';
import 'package:commet/rust/api/transcribe.dart' as rust;
import 'package:commet/ui/molecules/voice_message/voice_message_transcript.dart';
import 'package:commet/utils/voice_transcription.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;
  late SystemFileProvider voice;
  late StreamController<rust.TranscriptionEvent> events;
  late VoiceTranscription transcription;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync("vommet_transcript_ui_");
    final f = File(p.join(dir.path, "voice.ogg"))..writeAsBytesSync([1, 2]);
    voice = SystemFileProvider(f);
    events = StreamController();
    transcription = VoiceTranscription(
      baseDirectory: () async => dir,
      runner: (
              {required job,
              required modelPath,
              required audio,
              mimeType,
              language}) =>
          events.stream,
      cancelJob: (_) {},
      unloadModel: () {},
    );
    // Model already downloaded, so no confirmation dialog.
    final model = await transcription.modelFile(transcription.model);
    model.writeAsStringSync("model");
  });

  tearDown(() {
    dir.deleteSync(recursive: true);
  });

  // Stands in for VoiceMessagePlayer, which needs libmpv.
  Widget fakePlayer(
          {required FileProvider file,
          Duration? duration,
          List<int>? waveform,
          Widget? trailing,
          Widget? footer,
          Key? key}) =>
      Column(children: [
        Row(children: [const Text("waveform"), if (trailing != null) trailing]),
        if (footer != null) footer,
      ]);

  Widget app() => MaterialApp(
        home: Scaffold(
          body: TranscribableVoiceMessage(
              file: voice,
              mimeType: "audio/ogg",
              transcription: transcription,
              playerBuilder: fakePlayer),
        ),
      );

  testWidgets("→A, shimmer, text in the bubble, chevron folds it",
      (tester) async {
    await tester.pumpWidget(app());
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();
    expect(find.byIcon(Icons.arrow_forward_rounded), findsOneWidget);
    expect(find.byTooltip("Transcribe"), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.byTooltip("Transcribe"));
      await Future.delayed(const Duration(milliseconds: 100));
      events.add(const rust.TranscriptionEvent(progress: 40, cancelled: false));
      await Future.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    expect(find.byType(TranscriptShimmer), findsOneWidget);
    expect(find.byTooltip("Cancel transcription"), findsOneWidget);

    await tester.runAsync(() async {
      events.add(const rust.TranscriptionEvent(
          progress: 100,
          cancelled: false,
          result: rust.TranscriptionResult(
              text: "see you at eight", language: "en", confidence: 0.4)));
      await Future.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    expect(find.byType(TranscriptShimmer), findsNothing);
    expect(find.text("see you at eight"), findsOneWidget);
    expect(find.text("Low confidence: the text may be inaccurate."),
        findsOneWidget);
    expect(find.byIcon(Icons.keyboard_arrow_up), findsOneWidget);

    await tester.tap(find.byTooltip("Hide transcript"));
    await tester.pump();
    expect(find.text("see you at eight"), findsNothing);
    expect(find.byIcon(Icons.arrow_forward_rounded), findsOneWidget);

    await tester.tap(find.byTooltip("Show transcript"));
    await tester.pump();
    expect(find.text("see you at eight"), findsOneWidget);
  });

  testWidgets("a failure shows in the bubble and →A retries", (tester) async {
    await tester.pumpWidget(app());
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.byTooltip("Transcribe"));
      await Future.delayed(const Duration(milliseconds: 100));
      events.addError(Exception("unrecognised audio format"));
      await Future.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    expect(find.text("This voice message's audio format isn't supported."),
        findsOneWidget);
    expect(find.byTooltip("Transcribe"), findsOneWidget);
  });
}
