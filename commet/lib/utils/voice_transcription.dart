import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:commet/cache/file_cache.dart';
import 'package:commet/cache/file_provider.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/config/preferences/string_preference.dart';
import 'package:commet/main.dart' show fileCache;
import 'package:commet/rust/api/transcribe.dart' as rust;
import 'package:commet/rust/frb_generated.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Whisper models (whisper.cpp ggml format, q5_1-quantized: about 2.5 times
/// smaller than the full models and faster on weak CPUs, for a small accuracy
/// cost), downloaded on first use rather than shipped with the app. Sizes and
/// SHA-256 hashes are Hugging Face's records of the files at [revision].
enum TranscriptionModel {
  tiny("Tiny", 32152673,
      "818710568da3ca15689e31a743197b520007872ff9576237bda97bd1b469c3d7"),
  base("Base", 59707625,
      "422f1ae452ade6f30a004d7e5c6a43195e4433bc370bf23fac9cc591f01a8898"),
  small("Small", 190085487,
      "ae85e4a935d7a567bd102fe55afc16bb595bdb618e11b2fc7591bc08120411bb");

  const TranscriptionModel(this.label, this.bytes, this.sha256);

  final String label;
  final int bytes;
  final String sha256;

  String get fileName => "ggml-$name-q5_1.bin";

  /// Pinned to a commit of the model repository rather than `main`, so the
  /// files can't change under the hashes above.
  static const revision = "5359861c739e955e79d9a303bcbc70fb988958b1";

  Uri get url => Uri.parse(
      "https://huggingface.co/ggerganov/whisper.cpp/resolve/$revision/$fileName");

  /// "60 MB"
  String get sizeLabel => "${(bytes / 1000000).round()} MB";

  static TranscriptionModel byName(String name) => TranscriptionModel.values
      .firstWhere((m) => m.name == name, orElse: () => TranscriptionModel.base);
}

sealed class TranscriptState {
  const TranscriptState();
}

class TranscriptIdle extends TranscriptState {
  const TranscriptIdle();
}

/// The speech model is being downloaded; [progress] is 0..1, or null when
/// the size isn't known yet.
class TranscriptDownloading extends TranscriptState {
  const TranscriptDownloading(this.progress);
  final double? progress;
}

/// [progress] is 0..1.
class TranscriptRunning extends TranscriptState {
  const TranscriptRunning(this.progress);
  final double progress;
}

class TranscriptDone extends TranscriptState {
  const TranscriptDone(this.transcript);
  final Transcript transcript;
}

class TranscriptFailed extends TranscriptState {
  const TranscriptFailed(this.message);
  final String message;
}

class Transcript {
  const Transcript(
      {required this.text,
      this.language,
      required this.confidence,
      this.autoDetected = true});

  final String text;
  final String? language;

  /// Whether Whisper picked [language] itself, rather than being told it.
  final bool autoDetected;

  /// Mean token probability, 0..1.
  final double confidence;

  /// Below this, the text gets a "may be inaccurate" note. Clear speech
  /// scores around 0.9 with the base model.
  static const double lowConfidence = 0.6;

  bool get isLowConfidence => text.isNotEmpty && confidence < lowConfidence;

  Map<String, dynamic> toJson() => {
        "text": text,
        "language": language,
        "confidence": confidence,
        "auto": autoDetected,
      };

  static Transcript? fromJson(Object? json) {
    if (json is! Map) return null;
    final text = json["text"];
    final confidence = json["confidence"];
    if (text is! String || confidence is! num) return null;
    final language = json["language"];
    return Transcript(
        text: text,
        language: language is String ? language : null,
        confidence: confidence.toDouble(),
        autoDetected: json["auto"] != false);
  }
}

class TranscriptionModelException implements Exception {
  TranscriptionModelException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Runs one transcription; the default calls whisper.cpp in rust_lib_commet.
typedef TranscriptionRunner = Stream<rust.TranscriptionEvent> Function({
  required int job,
  required String modelPath,
  required List<int> audio,
  String? mimeType,
  String? language,
});

/// On-device transcription of voice messages (#70). Audio never leaves the
/// device: whisper.cpp runs locally on a model downloaded once. Transcripts
/// are cached on disk per file, so a second tap (or a restart) is instant.
///
/// State lives here rather than in the widgets so a running transcription
/// survives its message scrolling out of view.
class VoiceTranscription {
  VoiceTranscription({
    Future<Directory> Function()? baseDirectory,
    TranscriptionRunner? runner,
    void Function(int job)? cancelJob,
    void Function()? unloadModel,
    http.Client Function()? httpClient,
    FileCache? Function()? sealer,
  })  : _baseDirectory = baseDirectory ?? getApplicationSupportDirectory,
        _sealer = sealer ?? (() => fileCache),
        _runner = runner ?? _nativeRunner,
        // Nothing can be running or loaded before the library is.
        _cancelJob = cancelJob ??
            ((job) {
              if (RustLib.instance.initialized) {
                rust.cancelTranscription(job: job);
              } else {
                _cancelledWhileLoading.add(job);
              }
            }),
        _unloadModel = unloadModel ??
            (() {
              if (RustLib.instance.initialized) {
                rust.unloadTranscriptionModel();
              }
            }),
        _httpClient = httpClient ?? http.Client.new;

  static final VoiceTranscription instance = VoiceTranscription();

  /// Where the native side is built. main.dart loads it at startup on
  /// desktop; on Android it's loaded by the first transcription.
  static bool get supported =>
      PlatformUtils.isLinux ||
      PlatformUtils.isWindows ||
      PlatformUtils.isAndroid;

  static Future<void>? _loadingNative;
  static final Set<int> _cancelledWhileLoading = {};

  static Stream<rust.TranscriptionEvent> _nativeRunner({
    required int job,
    required String modelPath,
    required List<int> audio,
    String? mimeType,
    String? language,
  }) async* {
    if (!RustLib.instance.initialized) {
      // A failed load throws into this transcription; let the next one retry.
      await (_loadingNative ??=
          RustLib.init().whenComplete(() => _loadingNative = null));
      if (_cancelledWhileLoading.remove(job)) {
        yield const rust.TranscriptionEvent(progress: 0, cancelled: true);
        return;
      }
    }
    yield* rust.transcribeVoiceMessage(
        job: job,
        modelPath: modelPath,
        audio: audio,
        mimeType: mimeType,
        language: language);
  }

  static final StringPreference modelPreference = StringPreference(
      "voice_transcription_model",
      defaultValue: TranscriptionModel.base.name);

  /// A Whisper language code, or "auto" to detect it per message.
  static final StringPreference languagePreference =
      StringPreference("voice_transcription_language", defaultValue: "auto");

  final Future<Directory> Function() _baseDirectory;

  /// Vommet: seals saved transcripts (the app's media cache).
  final FileCache? Function() _sealer;
  final TranscriptionRunner _runner;
  final void Function(int job) _cancelJob;
  final void Function() _unloadModel;
  final http.Client Function() _httpClient;

  final Map<String, ValueNotifier<TranscriptState>> _states = {};
  final Map<String, int> _jobs = {};
  final Set<String> _waitingForModel = {};

  /// Cancelled while the voice message was still being loaded, before its
  /// job started.
  final Set<String> _cancelledBeforeJob = {};
  int _nextJob = 1;

  /// The running model download, shared by every message waiting for it.
  Future<File>? _download;
  http.Client? _downloadClient;

  /// Set by [cancelDownload]; covers a cancel that lands before the running
  /// download has created its HTTP client (closing it then does nothing).
  bool _downloadCancelled = false;
  final ValueNotifier<double?> downloadProgress = ValueNotifier(null);

  TranscriptionModel get model =>
      TranscriptionModel.byName(modelPreference.value);

  String? get language {
    final l = languagePreference.value;
    return l == "auto" ? null : l;
  }

  Future<Directory> _dir(String name) async {
    final dir = Directory(p.join((await _baseDirectory()).path, name));
    await dir.create(recursive: true);
    return dir;
  }

  Future<File> modelFile(TranscriptionModel model) async =>
      File(p.join((await _dir("whisper")).path, model.fileName));

  Future<bool> isDownloaded(TranscriptionModel model) async =>
      (await modelFile(model)).exists();

  /// Downloaded models and their size on disk.
  Future<Map<TranscriptionModel, int>> downloadedModels() async {
    final result = <TranscriptionModel, int>{};
    for (final m in TranscriptionModel.values) {
      final f = await modelFile(m);
      if (await f.exists()) result[m] = await f.length();
    }
    return result;
  }

  Future<void> deleteModel(TranscriptionModel model) async {
    _unloadModel();
    final f = await modelFile(model);
    if (await f.exists()) await f.delete();
  }

  /// Downloads [model] to a temporary file, checks its hash, then moves it
  /// into place. Throws [TranscriptionModelException] on a bad download.
  Future<File> downloadModel(TranscriptionModel model) {
    final running = _download;
    if (running != null) return running;
    // Reset before starting: _downloadModel runs synchronously up to its
    // first await, and a cancel from in there must stick.
    _downloadCancelled = false;
    return _download = _downloadModel(model).whenComplete(() {
      _download = null;
      _downloadClient = null;
      downloadProgress.value = null;
    });
  }

  void cancelDownload() {
    _downloadCancelled = true;
    _downloadClient?.close();
  }

  Future<File> _downloadModel(TranscriptionModel model) async {
    final target = await modelFile(model);
    if (await target.exists()) return target;
    // No await between here and downloadVerified creating its client, so a
    // later cancel always finds the client to close.
    if (_downloadCancelled) {
      throw TranscriptionModelException("The model download was canceled.");
    }
    return downloadVerified(model.url, model.sha256, target,
        expectedBytes: model.bytes);
  }

  /// Streams [url] to `[target].part`, hashing as it goes, and renames it to
  /// [target] only when the SHA-256 matches.
  Future<File> downloadVerified(Uri url, String expectedSha256, File target,
      {int? expectedBytes}) async {
    final part = File("${target.path}.part");
    final client = _downloadClient = _httpClient();
    downloadProgress.value = 0;
    try {
      final response = await client.send(http.Request("GET", url));
      if (response.statusCode != 200) {
        throw TranscriptionModelException(
            "The model download failed (HTTP ${response.statusCode}).");
      }
      final total = response.contentLength ?? expectedBytes;
      var received = 0;
      final digestSink = _DigestSink();
      final hasher = sha256.startChunkedConversion(digestSink);
      final out = part.openWrite();
      try {
        await for (final chunk in response.stream) {
          out.add(chunk);
          hasher.add(chunk);
          received += chunk.length;
          if (total != null && total > 0) {
            downloadProgress.value = (received / total).clamp(0.0, 1.0);
          }
        }
      } finally {
        await out.close();
      }
      hasher.close();
      if (digestSink.value.toString() != expectedSha256) {
        throw TranscriptionModelException(
            "The downloaded model is damaged. Try again.");
      }
      return await part.rename(target.path);
    } on http.ClientException catch (e) {
      throw TranscriptionModelException(
          "The model download failed: ${e.message}.");
    } finally {
      client.close();
      if (await part.exists()) await part.delete();
    }
  }

  /// Live state for the voice message stored as [key] (its file identifier,
  /// i.e. the mxc URI, so forwarded copies share a transcript).
  ValueNotifier<TranscriptState> stateFor(String key) {
    final existing = _states[key];
    if (existing != null) return existing;
    final notifier = ValueNotifier<TranscriptState>(const TranscriptIdle());
    _states[key] = notifier;
    _loadCached(key).then((t) {
      if (t != null && notifier.value is TranscriptIdle) {
        notifier.value = TranscriptDone(t);
      }
    });
    return notifier;
  }

  // Vommet: transcripts of voice messages (often from encrypted rooms) are
  // sealed with the media cache's key, under names derived from that key,
  // so they are never on disk in plaintext and go with the key at sign-out
  // (they are deleted then too). With no media cache there's no saved
  // transcript. They used to be plain JSON files: those are deleted.

  Future<Directory>? _transcripts;

  /// The transcripts' directory; the old plaintext ones (".json") are
  /// deleted the first time (and at start-up, [deleteLegacyTranscripts]).
  Future<Directory> _transcriptDirectory() => _transcripts ??= () async {
        final dir = await _dir("voice_transcripts");
        await deleteLegacyTranscripts();
        return dir;
      }()
          .catchError((Object error) {
        _transcripts = null;
        throw error;
      });

  /// Vommet: deletes the plaintext transcripts (".json") saved before they
  /// were sealed. Run at start-up, so they don't wait for the next voice
  /// message. Returns how many went; never throws.
  Future<int> deleteLegacyTranscripts() async {
    var count = 0;
    try {
      final dir =
          Directory(p.join((await _baseDirectory()).path, "voice_transcripts"));
      if (!await dir.exists()) return 0;
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is File && entity.path.endsWith(".json")) {
          try {
            await entity.delete();
            count++;
          } catch (_) {}
        }
      }
    } catch (_) {}
    return count;
  }

  static String _sealedId(String key) => "voice-transcript:$key";

  Future<File?> _cacheFile(FileCache cache, String key) async {
    final name = await cache.dataNameOf(_sealedId(key));
    if (name == null) return null;
    return File(p.join((await _transcriptDirectory()).path, "$name.vt"));
  }

  Future<Transcript?> _loadCached(String key) async {
    final cache = _sealer();
    if (cache == null) return null;
    try {
      final f = await _cacheFile(cache, key);
      if (f == null || !await f.exists()) return null;
      final plain = await cache.openData(_sealedId(key), await f.readAsBytes());
      if (plain == null) {
        // Sealed under a key that is gone, or damaged.
        await f.delete();
        return null;
      }
      return Transcript.fromJson(jsonDecode(utf8.decode(plain)));
    } catch (_) {
      return null;
    }
  }

  Future<void> _storeCached(String key, Transcript t) async {
    final cache = _sealer();
    if (cache == null) return;
    try {
      final sealed = await cache.sealData(_sealedId(key),
          Uint8List.fromList(utf8.encode(jsonEncode(t.toJson()))));
      final f = await _cacheFile(cache, key);
      if (sealed == null || f == null) return;
      final temp = File("${f.path}.tmp");
      await temp.writeAsBytes(sealed, flush: true);
      await temp.rename(f.path);
    } catch (_) {
      // Only a cache.
    }
  }

  /// Deletes every saved transcript (the settings button, and sign-out).
  Future<void> clearTranscripts() async {
    _transcripts = null;
    final dir =
        Directory(p.join((await _baseDirectory()).path, "voice_transcripts"));
    if (await dir.exists()) await dir.delete(recursive: true);
    for (final s in _states.values) {
      if (s.value is TranscriptDone) s.value = const TranscriptIdle();
    }
  }

  /// Transcribes [file], downloading the model first if needed (callers ask
  /// the user before that). Progress and the result arrive on [stateFor].
  Future<void> transcribe(FileProvider file, {String? mimeType}) async {
    final key = file.fileIdentifier;
    final state = stateFor(key);
    if (state.value is TranscriptRunning ||
        state.value is TranscriptDownloading) {
      return;
    }

    try {
      final model = this.model;
      var path = await modelFile(model);
      if (!await path.exists()) {
        _waitingForModel.add(key);
        void onProgress() {
          if (_waitingForModel.contains(key)) {
            state.value = TranscriptDownloading(downloadProgress.value);
          }
        }

        state.value = TranscriptDownloading(downloadProgress.value);
        downloadProgress.addListener(onProgress);
        try {
          // A listener on the state may already have cancelled.
          if (!_waitingForModel.contains(key)) return;
          path = await downloadModel(model);
        } catch (_) {
          // cancel() already reset the state.
          if (!_waitingForModel.contains(key)) return;
          rethrow;
        } finally {
          downloadProgress.removeListener(onProgress);
        }
        if (!_waitingForModel.remove(key)) return; // cancelled meanwhile
      }

      state.value = const TranscriptRunning(0);
      final Uint8List? bytes = await file.getFileData();
      if (bytes == null) {
        state.value =
            const TranscriptFailed("Couldn't load the voice message.");
        return;
      }

      if (_cancelledBeforeJob.remove(key)) {
        state.value = const TranscriptIdle();
        return;
      }

      final language = this.language;
      final job = _nextJob++;
      _jobs[key] = job;
      await for (final event in _runner(
          job: job,
          modelPath: path.path,
          audio: bytes,
          mimeType: mimeType,
          language: language)) {
        if (event.cancelled) {
          state.value = const TranscriptIdle();
          return;
        }
        final result = event.result;
        if (result != null) {
          final t = Transcript(
              text: result.text,
              language: result.language,
              confidence: result.confidence,
              autoDetected: language == null);
          await _storeCached(key, t);
          state.value = TranscriptDone(t);
          return;
        }
        state.value = TranscriptRunning((event.progress / 100).clamp(0.0, 1.0));
      }
    } on TranscriptionModelException catch (e) {
      state.value = TranscriptFailed(e.message);
    } catch (e) {
      state.value = TranscriptFailed(describeError(e));
    } finally {
      _jobs.remove(key);
      _waitingForModel.remove(key);
      _cancelledBeforeJob.remove(key);
    }
  }

  void cancel(String key) {
    final job = _jobs[key];
    if (job != null) {
      _cancelJob(job);
      return;
    }
    if (_waitingForModel.remove(key)) {
      _states[key]?.value = const TranscriptIdle();
      // Stop the download only when nobody else is waiting for it.
      if (_waitingForModel.isEmpty) cancelDownload();
      return;
    }
    // Still loading the voice message: stop before the job starts.
    if (_states[key]?.value is TranscriptRunning) {
      _cancelledBeforeJob.add(key);
      _states[key]?.value = const TranscriptIdle();
    }
  }

  static String describeError(Object e) {
    final text = e.toString();
    if (text.contains("AVX2")) {
      return "This computer's processor can't run transcription (it needs AVX2).";
    }
    if (text.contains("unrecognised audio format") ||
        text.contains("unsupported audio codec") ||
        text.contains("no audio track")) {
      return "This voice message's audio format isn't supported.";
    }
    return "Couldn't transcribe this voice message.";
  }
}

class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
