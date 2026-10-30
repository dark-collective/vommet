import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:commet/cache/drift_file_cache.dart';
import 'package:commet/cache/media_cache_key.dart';
import 'package:commet/security/key_vault/key_vault.dart';
import 'package:commet/cache/file_provider.dart';
import 'package:commet/rust/api/transcribe.dart' as rust;
import 'package:commet/utils/voice_transcription.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/test_key_vault.dart';

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
  late DriftFileCache cache;
  late KeyVault vault;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp("vommet_transcription_");
    // Vommet: saved transcripts are sealed with the media cache's key.
    vault = await testKeyVault(p.join(dir.path, "keys"));
    cache = DriftFileCache(
        cacheDir: p.join(dir.path, "media_cache"),
        keySource: VaultMediaCacheKey(vault),
        tempDir: p.join(dir.path, "tmp"));
    cache.database = DriftFileCacheDatabase(NativeDatabase.memory());
    final f = File(p.join(dir.path, "voice.ogg"));
    await f.writeAsBytes([1, 2, 3, 4]);
    voice = SystemFileProvider(f);
  });

  tearDown(() async {
    await cache.database?.close();
    cache.database = null;
    await vault.dispose();
    // stateFor looks up a saved transcript in the background: a key load
    // it started may still be making the cache folder.
    for (var attempt = 0;; attempt++) {
      try {
        await dir.delete(recursive: true);
        break;
      } on FileSystemException {
        if (attempt >= 20) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
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
        sealer: () => cache,
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

    test("old plaintext transcripts are deleted at start-up", () async {
      final t = make();
      expect(await t.deleteLegacyTranscripts(), 0);
      final folder = Directory(p.join(dir.path, "voice_transcripts"));
      await folder.create(recursive: true);
      await File(p.join(folder.path, "a.json")).writeAsString("{}");
      await File(p.join(folder.path, "b.vt")).writeAsString("x");
      expect(await t.deleteLegacyTranscripts(), 1);
      expect(await File(p.join(folder.path, "a.json")).exists(), isFalse);
      expect(await File(p.join(folder.path, "b.vt")).exists(), isTrue);
    });

    test("saved transcripts are sealed and go with the cache key", () async {
      // An old plaintext transcript from before they were sealed.
      final transcripts = Directory(p.join(dir.path, "voice_transcripts"));
      await transcripts.create(recursive: true);
      final legacy = File(p.join(transcripts.path, "old.json"));
      await legacy.writeAsString('{"text":"old words"}');

      final t = make(runner: (
          {required job,
          required modelPath,
          required audio,
          mimeType,
          language}) async* {
        yield done("very private words");
      });
      await installModel(t);
      await t.transcribe(voice, mimeType: "audio/ogg");
      expect(await legacy.exists(), isFalse);

      final files = transcripts.listSync().whereType<File>().toList();
      expect(files, hasLength(1));
      expect(p.basename(files.single.path), endsWith(".vt"));
      expect(p.basename(files.single.path).contains("voice"), isFalse);
      expect(utf8.decode(files.single.readAsBytesSync(), allowMalformed: true),
          isNot(contains("private")));

      // Another instance with the same key reads it back.
      final again = make();
      final cached =
          await stateOf<TranscriptDone>(again.stateFor(voice.fileIdentifier));
      expect(cached.transcript.text, "very private words");

      // Once the key is forgotten (sign-out), it can't be read any more.
      await cache.forgetSensitive();
      final later = make();
      final state = later.stateFor(voice.fileIdentifier);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(state.value, isA<TranscriptIdle>());
    });

    test("without a media cache nothing is saved", () async {
      final t = VoiceTranscription(
        baseDirectory: () async => dir,
        runner: (
            {required job,
            required modelPath,
            required audio,
            mimeType,
            language}) async* {
          yield done("words");
        },
        cancelJob: (_) {},
        unloadModel: () {},
        sealer: () => null,
      );
      await installModel(t);
      await t.transcribe(voice, mimeType: "audio/ogg");
      final transcripts = Directory(p.join(dir.path, "voice_transcripts"));
      expect(
          transcripts.existsSync()
              ? transcripts.listSync().whereType<File>()
              : [],
          isEmpty);
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
