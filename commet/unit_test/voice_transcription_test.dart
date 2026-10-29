import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:commet/cache/file_provider.dart';
import 'package:commet/rust/api/transcribe.dart' as rust;
import 'package:commet/utils/voice_transcription.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

rust.TranscriptionEvent progress(int p) =>
    rust.TranscriptionEvent(progress: p, cancelled: false);

rust.TranscriptionEvent done(String text, {double confidence = 0.9}) =>
    rust.TranscriptionEvent(
        progress: 100,
        cancelled: false,
        result: rust.TranscriptionResult(
            text: text, language: "en", confidence: confidence));

/// A voice message whose download only finishes when [release] completes.
class SlowFileProvider extends SystemFileProvider {
  SlowFileProvider(super.file);

  final release = Completer<void>();

  @override
  Future<Uint8List?> getFileData() async {
    await release.future;
    return super.getFileData();
  }
}

/// Waits until [notifier] holds a [T] (that also passes [where]). Listens
/// instead of polling, so a slow machine only makes it take longer.
Future<T> stateOf<T>(ValueNotifier<TranscriptState> notifier,
    {bool Function(T state)? where}) async {
  bool reached() {
    final v = notifier.value;
    return v is T && (where == null || where(v as T));
  }

  if (!reached()) {
    final done = Completer<void>();
    void check() {
      if (reached() && !done.isCompleted) done.complete();
    }

    notifier.addListener(check);
    try {
      await done.future.timeout(const Duration(seconds: 20),
          onTimeout: () => fail("never reached $T; last ${notifier.value}"));
    } finally {
      notifier.removeListener(check);
    }
  }
  return notifier.value as T;
}

void main() {
  late Directory dir;
  late SystemFileProvider voice;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp("vommet_transcription_");
    final f = File(p.join(dir.path, "voice.ogg"));
    await f.writeAsBytes([1, 2, 3, 4]);
    voice = SystemFileProvider(f);
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  VoiceTranscription make({
    TranscriptionRunner? runner,
    void Function(int)? cancelJob,
    http.Client Function()? client,
    Future<Directory> Function()? baseDirectory,
  }) =>
      VoiceTranscription(
        baseDirectory: baseDirectory ?? () async => dir,
        runner: runner,
        cancelJob: cancelJob ?? (_) {},
        unloadModel: () {},
        httpClient: client,
      );

  Future<void> installModel(VoiceTranscription t) async {
    final f = await t.modelFile(t.model);
    await f.writeAsString("model");
  }

  group("Transcript", () {
    test("JSON round trip", () {
      const t = Transcript(text: "hello", language: "en", confidence: 0.5);
      final back = Transcript.fromJson(jsonDecode(jsonEncode(t.toJson())))!;
      expect(back.text, "hello");
      expect(back.language, "en");
      expect(back.confidence, 0.5);
      expect(back.autoDetected, true);
    });

    test("remembers a language set in Settings", () {
      const t = Transcript(
          text: "hola", language: "es", confidence: 0.9, autoDetected: false);
      final back = Transcript.fromJson(jsonDecode(jsonEncode(t.toJson())))!;
      expect(back.autoDetected, false);
      // Transcripts cached before this field count as auto-detected.
      expect(Transcript.fromJson({"text": "x", "confidence": 1})!.autoDetected,
          true);
    });

    test("malformed JSON is ignored", () {
      expect(Transcript.fromJson(null), isNull);
      expect(Transcript.fromJson({"text": 3, "confidence": 1}), isNull);
      expect(Transcript.fromJson({"text": "x"}), isNull);
    });

    test("low confidence only flags non-empty text", () {
      expect(
          const Transcript(text: "x", confidence: 0.3).isLowConfidence, true);
      expect(
          const Transcript(text: "x", confidence: 0.9).isLowConfidence, false);
      expect(const Transcript(text: "", confidence: 0).isLowConfidence, false);
    });
  });

  test("unknown model names fall back to base", () {
    expect(TranscriptionModel.byName("small"), TranscriptionModel.small);
    expect(TranscriptionModel.byName("huge"), TranscriptionModel.base);
  });

  group("transcribe", () {
    test("reports progress, then the text, and caches it", () async {
      final calls = <String?>[];
      final t = make(runner: (
          {required job,
          required modelPath,
          required audio,
          mimeType,
          language}) async* {
        calls.add(mimeType);
        expect(audio, [1, 2, 3, 4]);
        expect(modelPath, endsWith("ggml-base-q5_1.bin"));
        yield progress(50);
        yield done("hello world");
      });
      await installModel(t);

      final state = t.stateFor(voice.fileIdentifier);
      final seen = <TranscriptState>[];
      state.addListener(() => seen.add(state.value));
      await t.transcribe(voice, mimeType: "audio/ogg");

      expect(calls, ["audio/ogg"]);
      expect(seen.whereType<TranscriptRunning>().map((s) => s.progress),
          containsAllInOrder([0.0, 0.5]));
      expect((state.value as TranscriptDone).transcript.text, "hello world");

      // A fresh instance (an app restart) finds it without transcribing.
      final again = make(runner: (
          {required job,
          required modelPath,
          required audio,
          mimeType,
          language}) {
        fail("should come from the cache");
      });
      final cached =
          await stateOf<TranscriptDone>(again.stateFor(voice.fileIdentifier));
      expect(cached.transcript.text, "hello world");

      await again.clearTranscripts();
      expect(again.stateFor(voice.fileIdentifier).value, isA<TranscriptIdle>());
      // Nothing left on disk for a later instance to find. (Not checked via
      // a fresh stateFor: its cache load is async, so it reads Idle at
      // first either way, and would still be running during tearDown.)
      final cacheDir = Directory(p.join(dir.path, "voice_transcripts"));
      expect(cacheDir.existsSync() ? cacheDir.listSync() : [], isEmpty);
    });

    test("cancel stops the native job and goes back to idle", () async {
      final cancelled = Completer<int>();
      final t = make(
        cancelJob: cancelled.complete,
        runner: (
            {required job,
            required modelPath,
            required audio,
            mimeType,
            language}) async* {
          yield progress(10);
          expect(await cancelled.future, job);
          yield const rust.TranscriptionEvent(progress: 0, cancelled: true);
        },
      );
      await installModel(t);
      final state = t.stateFor(voice.fileIdentifier);
      final running = t.transcribe(voice);
      // progress(10) arrives from the runner, so the native job exists.
      await stateOf<TranscriptRunning>(state, where: (s) => s.progress > 0);
      t.cancel(voice.fileIdentifier);
      await running;
      expect(state.value, isA<TranscriptIdle>());
    });

    test("cancel while the voice message is still loading", () async {
      var started = false;
      final t = make(runner: (
          {required job,
          required modelPath,
          required audio,
          mimeType,
          language}) async* {
        started = true;
        yield done("too late");
      });
      await installModel(t);
      final slow = SlowFileProvider(voice.file);
      final state = t.stateFor(slow.fileIdentifier);
      final running = t.transcribe(slow);
      await stateOf<TranscriptRunning>(state);
      t.cancel(slow.fileIdentifier);
      expect(state.value, isA<TranscriptIdle>());
      slow.release.complete();
      await running;
      expect(started, isFalse);
      expect(state.value, isA<TranscriptIdle>());
    });

    test("a native error becomes a readable failure", () async {
      final t = make(runner: (
          {required job,
          required modelPath,
          required audio,
          mimeType,
          language}) {
        return Stream.error(Exception("unsupported CPU: needs AVX2"));
      });
      await installModel(t);
      await t.transcribe(voice);
      final state = t.stateFor(voice.fileIdentifier).value as TranscriptFailed;
      expect(state.message, contains("AVX2"));
    });

    test("cancelling while the model downloads goes back to idle", () async {
      final requested = Completer<String>();
      final body = StreamController<List<int>>();
      final client = MockClient.streaming((request, _) async {
        requested.complete(request.url.host);
        return http.StreamedResponse(body.stream, 200, contentLength: 100);
      });
      final t = make(client: () => client);
      final state = t.stateFor(voice.fileIdentifier);
      final running = t.transcribe(voice);
      // Cancel mid-body, not before the request (that's the next test).
      expect(await requested.future, "huggingface.co");
      body.add([0]);
      await stateOf<TranscriptDownloading>(state);
      t.cancel(voice.fileIdentifier);
      expect(state.value, isA<TranscriptIdle>());
      // MockClient.close() can't abort a response; end it like a dropped
      // connection would.
      await body.close();
      await running;
      expect(state.value, isA<TranscriptIdle>());
      expect(await t.isDownloaded(t.model), false);
    });

    test("cancelling before the request goes out never fetches the model",
        () async {
      var requests = 0;
      final client = MockClient((_) async {
        requests++;
        return http.Response("", 200);
      });
      late VoiceTranscription t;
      t = make(
          client: () => client,
          baseDirectory: () async {
            // The download is looking up its target: no HTTP client yet.
            if (t.stateFor(voice.fileIdentifier).value
                is TranscriptDownloading) {
              t.cancel(voice.fileIdentifier);
            }
            return dir;
          });
      final state = t.stateFor(voice.fileIdentifier);
      await t.transcribe(voice);
      expect(state.value, isA<TranscriptIdle>());
      expect(requests, 0);
      expect(await t.isDownloaded(t.model), false);
    });
  });

  group("downloadVerified", () {
    final bytes = utf8.encode("pretend this is a whisper model");
    final hash = sha256.convert(bytes).toString();

    test("keeps a file with the right hash", () async {
      final t = make(
          client: () =>
              MockClient((_) async => http.Response.bytes(bytes, 200)));
      final target = File(p.join(dir.path, "model.bin"));
      await t.downloadVerified(
          Uri.parse("https://example.org/m"), hash, target);
      expect(await target.readAsBytes(), bytes);
      expect(t.downloadProgress.value, 1.0);
      expect(await File("${target.path}.part").exists(), false);
    });

    test("rejects a damaged download and leaves nothing behind", () async {
      final t = make(
          client: () =>
              MockClient((_) async => http.Response.bytes([...bytes, 0], 200)));
      final target = File(p.join(dir.path, "model.bin"));
      await expectLater(
          t.downloadVerified(Uri.parse("https://example.org/m"), hash, target),
          throwsA(isA<TranscriptionModelException>()));
      expect(await target.exists(), false);
      expect(await File("${target.path}.part").exists(), false);
    });

    test("reports HTTP errors", () async {
      final t = make(
          client: () => MockClient((_) async => http.Response("nope", 404)));
      await expectLater(
          t.downloadVerified(Uri.parse("https://example.org/m"), hash,
              File(p.join(dir.path, "model.bin"))),
          throwsA(isA<TranscriptionModelException>()
              .having((e) => e.message, "message", contains("404"))));
    });
  });
}
