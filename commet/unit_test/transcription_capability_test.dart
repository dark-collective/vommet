import 'dart:io';

import 'package:commet/cache/file_provider.dart';
import 'package:commet/client/attachment.dart';
import 'package:commet/rust/api/transcribe.dart' as rust;
import 'package:commet/rust/frb_generated.dart';
import 'package:commet/ui/atoms/message_attachment.dart';
import 'package:commet/utils/voice_transcription.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:media_kit/media_kit.dart';

class _TranscriptionBuild implements RustLibApi {
  bool supported = false;

  @override
  bool crateApiTranscribeTranscriptionSupported() => supported;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final build = _TranscriptionBuild();

  setUpAll(() {
    RustLib.initMock(api: build);
  });

  testWidgets(
      'an Android voice attachment offers transcription only with native support',
      (tester) async {
    MediaKit.ensureInitialized();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final voice = AudioAttachment(
      SystemFileProvider(File('voice.ogg')),
      name: 'voice.ogg',
      mimeType: 'audio/ogg',
      isVoice: true,
      duration: const Duration(seconds: 12),
      waveform: List.generate(48, (index) => (index * 287) % 1024),
    );

    final app = MaterialApp(
      theme: ThemeData.dark().copyWith(platform: TargetPlatform.android),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(12),
          child: MessageAttachment(voice),
        ),
      ),
    );

    build.supported = false;
    await tester.pumpWidget(app);
    expect(find.byTooltip('Play voice message'), findsOneWidget);
    expect(find.byTooltip('Transcribe'), findsNothing);

    build.supported = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(app);
    expect(find.byTooltip('Play voice message'), findsOneWidget);
    expect(find.byTooltip('Transcribe'), findsOneWidget);
  }, variant: const TargetPlatformVariant({TargetPlatform.android}));

  test('an unsupported native build does not request a speech model', () async {
    build.supported = false;
    final directory =
        Directory.systemTemp.createTempSync('transcription_capability_');
    addTearDown(() => directory.deleteSync(recursive: true));
    final voice = SystemFileProvider(File('${directory.path}/voice.ogg'));
    var requests = 0;
    final service = VoiceTranscription(
      baseDirectory: () async => directory,
      httpClient: () => MockClient((request) async {
        requests++;
        return http.Response('', 503);
      }),
    );
    await service.transcribe(voice);
    expect(requests, 0);
  });

  test('an unsupported build skips the runner even with a cached model',
      () async {
    build.supported = false;
    final directory =
        Directory.systemTemp.createTempSync('transcription_cached_capability_');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/voice.ogg')..writeAsBytesSync([1, 2]);
    final voice = SystemFileProvider(file);
    var runnerCalls = 0;
    final service = VoiceTranscription(
      baseDirectory: () async => directory,
      sealer: () => null,
      runner: ({
        required job,
        required modelPath,
        required audio,
        mimeType,
        language,
      }) async* {
        runnerCalls++;
        yield const rust.TranscriptionEvent(progress: 100, cancelled: true);
      },
    );
    (await service.modelFile(service.model)).writeAsStringSync('fixture model');
    await service.transcribe(voice);
    expect(runnerCalls, 0);
  });
}
