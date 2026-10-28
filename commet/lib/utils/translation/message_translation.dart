import 'dart:async';
import 'dart:io';

import 'package:commet/config/preferences/bool_preference.dart';
import 'package:commet/config/preferences/string_list_preference.dart';
import 'package:commet/config/preferences/string_preference.dart';
import 'package:commet/utils/translation/engine.dart';
import 'package:commet/utils/translation/model_spec.dart';
import 'package:commet/utils/translation/models.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

sealed class TranslationState {
  const TranslationState();
}

class TranslationIdle extends TranslationState {
  const TranslationIdle();
}

/// Language models are being downloaded; [progress] is 0..1, or null when
/// the size isn't known yet.
class TranslationDownloading extends TranslationState {
  const TranslationDownloading(this.progress);
  final double? progress;
}

class TranslationRunning extends TranslationState {
  const TranslationRunning();
}

class TranslationDone extends TranslationState {
  const TranslationDone(this.text, {required this.from, required this.to});
  final String text;
  final String from;
  final String to;
}

class TranslationFailed extends TranslationState {
  const TranslationFailed(this.message);
  final String message;
}

class TranslationModelException implements Exception {
  TranslationModelException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// On-device translation of messages (Vommet issue 680). Text never leaves
/// the device: Bergamot (Firefox Translations' engine) runs locally on
/// language models downloaded once from Mozilla. Directions without English
/// go through English (two models). Translations are kept in memory only.
///
/// State lives here rather than in the widgets so a running translation
/// survives its message scrolling out of view.
class MessageTranslation {
  MessageTranslation({
    TranslationEngine? engine,
    Future<Directory> Function()? baseDirectory,
    http.Client Function()? httpClient,
    List<TranslationModelSpec>? specs,
    bool? android,
    String Function()? systemLanguage,
  })  : _engine = engine,
        _baseDirectory = baseDirectory ?? getApplicationSupportDirectory,
        _httpClient = httpClient ?? http.Client.new,
        _specs = specs ?? translationModelSpecs,
        _android = android ?? (!kIsWeb && Platform.isAndroid),
        _systemLanguage = systemLanguage ?? _platformLanguage;

  static final MessageTranslation instance = MessageTranslation();

  /// A language code from [translationLanguageNames], or "auto" for the
  /// system language (English when it isn't one of them).
  static final StringPreference languagePreference =
      StringPreference("message_translation_language", defaultValue: "auto");

  /// Settings › App › Translation: "Translate button on messages". Off hides
  /// the Translate button on messages (and voice transcripts); rooms with
  /// "Translate this room" on still translate.
  static final BoolPreference buttonPreference =
      BoolPreference("message_translation_button", defaultValue: true);

  /// Settings › App › Language › Translation: the master switch (Vommet
  /// issue 820). Off hides every translation offer and pauses rooms with
  /// "Translate this room" on; they resume when it's switched back on.
  static final BoolPreference enabledPreference =
      BoolPreference("message_translation_enabled", defaultValue: true);

  static bool get translationEnabled => enabledPreference.value;

  /// Settings › App › Language › Translation: "Languages I read" (Vommet
  /// issue 821). Messages and rooms in these languages (or the translation
  /// language) get no translation offers.
  static final StringListPreference readPreference = StringListPreference(
      "message_translation_read_languages",
      defaultValue: const []);

  TranslationEngine? _engine;
  final Future<Directory> Function() _baseDirectory;
  final http.Client Function() _httpClient;
  final List<TranslationModelSpec> _specs;
  final bool _android;
  final String Function() _systemLanguage;

  TranslationEngine get engine => _engine ??= TranslationEngine.create();

  /// Whether this device can run translation at all.
  bool get available => engine.available;

  /// Whether translation is offered: the device can run it and the master
  /// switch is on.
  bool get supported => available && translationEnabled;

  /// The extra languages you read, besides [targetLanguage].
  List<String> get readLanguages => readPreference.value
      .where(
          (c) => c != targetLanguage && translationLanguageNames.containsKey(c))
      .toList();

  /// Whether you read [code]: it's your translation language or one of the
  /// "Languages I read".
  bool readsLanguage(String code) {
    final language = normalizeLanguage(code) ?? code;
    return language == targetLanguage ||
        readPreference.value.contains(language);
  }

  Future<void> setReadLanguages(List<String> codes) =>
      readPreference.set(codes.toSet().toList());

  final Map<String, ValueNotifier<TranslationState>> _states = {};
  final Map<String, String?> _detected = {};

  /// Running downloads by model key, shared by every message waiting.
  final Map<String, Future<void>> _downloads = {};
  final Map<String, http.Client> _downloadClients = {};
  final Set<String> _cancelledDownloads = {};

  /// Messages waiting for a download, by event id.
  final Set<String> _waiting = {};
  final ValueNotifier<double?> downloadProgress = ValueNotifier(null);

  /// Bumped when models are downloaded or deleted (settings page).
  final ValueNotifier<int> modelsChanged = ValueNotifier(0);

  /// The language messages are translated into.
  String get targetLanguage {
    final chosen = languagePreference.value;
    if (chosen != "auto" && targetLanguages.contains(chosen)) {
      return chosen;
    }
    return automaticLanguage;
  }

  /// What "auto" means here: the system language when messages can be
  /// translated into it, else English.
  String get automaticLanguage {
    final system = _systemLanguage();
    return targetLanguages.contains(system) ? system : "en";
  }

  /// The languages messages can be translated into on this platform, by name.
  List<String> get targetLanguages {
    final codes = {
      "en",
      for (final s in _specs)
        if (_fits(s)) s.to,
    }.toList();
    codes.sort((a, b) =>
        translationLanguageName(a).compareTo(translationLanguageName(b)));
    return codes;
  }

  /// Sets the language messages are translated into ("auto" for the system
  /// language). Messages already on screen pick it up when rebuilt.
  Future<void> setTargetLanguage(String code) async {
    await languagePreference.set(code);
    _detected.clear();
    for (final state in _states.values) {
      if (state.value is TranslationDone || state.value is TranslationFailed) {
        state.value = const TranslationIdle();
      }
    }
  }

  static String _platformLanguage() {
    final l = PlatformDispatcher.instance.locale;
    return normalizeLanguage(l.languageCode,
            script: l.scriptCode, country: l.countryCode) ??
        "en";
  }

  /// Maps a locale or CLD2 language code to the catalog's codes.
  static String? normalizeLanguage(String code,
      {String? script, String? country}) {
    final c = code.toLowerCase();
    switch (c) {
      case "un" || "":
        return null;
      case "iw":
        return "he";
      case "no" || "nn":
        return "nb";
      case "fil":
        return "tl";
      case "zh-hant":
        return "zh-Hant";
      case "zh" || "zh-hans":
        final traditional = script == "Hant" ||
            const {"TW", "HK", "MO"}.contains(country?.toUpperCase());
        return traditional ? "zh-Hant" : "zh-Hans";
    }
    return translationLanguageNames.containsKey(c) ? c : null;
  }

  bool _fits(TranslationModelSpec s) => switch (s.platforms) {
        ModelPlatforms.all => true,
        ModelPlatforms.desktop => !_android,
        ModelPlatforms.android => _android,
      };

  TranslationModelSpec? _spec(String from, String to) {
    for (final s in _specs) {
      if (s.from == from && s.to == to && _fits(s)) return s;
    }
    return null;
  }

  /// The models that translate [from] into [to]: one, or two through
  /// English. Null when there's no way.
  List<TranslationModelSpec>? route(String from, String to) {
    if (from == to) return null;
    final direct = _spec(from, to);
    if (direct != null) return [direct];
    if (from == "en" || to == "en") return null;
    final a = _spec(from, "en"), b = _spec("en", to);
    return a != null && b != null ? [a, b] : null;
  }

  /// Every language some route reaches from [from], by name (the composer's
  /// "Translate into" menu, Vommet issue 680 phase 2).
  List<String> reachableFrom(String from) {
    final codes = <String>{
      for (final s in _specs)
        if (_fits(s)) ...[s.from, s.to]
    }..remove(from);
    final result = [
      for (final c in codes)
        if (route(from, c) != null) c
    ];
    result.sort((a, b) =>
        translationLanguageName(a).compareTo(translationLanguageName(b)));
    return result;
  }

  /// A reliable guess at [text]'s language in the catalog's codes, else null.
  String? detectLanguage(String text) {
    if (!supported || text.trim().isEmpty) return null;
    final guess = engine.detect(text);
    return guess != null && guess.reliable
        ? normalizeLanguage(guess.code)
        : null;
  }

  /// The language of something you wrote: a reliable guess, else your
  /// translation language (short drafts often can't be told).
  String draftLanguage(String text) => detectLanguage(text) ?? targetLanguage;

  /// The language of [text] when it's one we can translate into
  /// [targetLanguage], else null. Cached per [eventId].
  /// Null too when translation is off or you read that language.
  String? translatableLanguage(String eventId, String text) {
    if (!supported) return null;
    if (_detected.containsKey(eventId)) return _readable(_detected[eventId]);
    String? result;
    if (text.trim().isNotEmpty) {
      final guess = engine.detect(text);
      final code = guess != null && guess.reliable
          ? normalizeLanguage(guess.code)
          : null;
      if (code != null && route(code, targetLanguage) != null) result = code;
    }
    _detected[eventId] = result;
    return _readable(result);
  }

  String? _readable(String? code) =>
      code == null || readsLanguage(code) ? null : code;

  Future<Directory> _modelsDir() async {
    final dir =
        Directory(p.join((await _baseDirectory()).path, "translation_models"));
    await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> modelDirectory(TranslationModelSpec spec) async =>
      Directory(p.join((await _modelsDir()).path, spec.directory));

  /// Every file is there and checked (written last, after the hashes).
  Future<File> _completeMarker(TranslationModelSpec spec) async =>
      File(p.join((await modelDirectory(spec)).path, ".complete"));

  Future<bool> isDownloaded(TranslationModelSpec spec) async =>
      (await _completeMarker(spec)).exists();

  Future<List<TranslationModelSpec>> missingModels(
      List<TranslationModelSpec> route) async {
    final missing = <TranslationModelSpec>[];
    for (final s in route) {
      if (!await isDownloaded(s)) missing.add(s);
    }
    return missing;
  }

  /// Downloaded models and their size on disk.
  Future<Map<TranslationModelSpec, int>> downloadedModels() async {
    final result = <TranslationModelSpec, int>{};
    for (final s in _specs) {
      if (!_fits(s) || !await isDownloaded(s)) continue;
      var size = 0;
      await for (final f in (await modelDirectory(s)).list()) {
        if (f is File) size += await f.length();
      }
      result[s] = size;
    }
    return result;
  }

  Future<void> deleteModel(TranslationModelSpec spec) async {
    await engine.unloadAll();
    final dir = await modelDirectory(spec);
    if (await dir.exists()) await dir.delete(recursive: true);
    modelsChanged.value++;
  }

  /// Downloads every file of [spec], each checked against its pinned hash.
  /// [onProgress] gets 0..1 over the whole model.
  Future<void> downloadModel(TranslationModelSpec spec,
      {void Function(double)? onProgress}) {
    final running = _downloads[spec.key];
    if (running != null) return running;
    _cancelledDownloads.remove(spec.key);
    final future = _downloadModel(spec, onProgress).whenComplete(() {
      _downloads.remove(spec.key);
      _downloadClients.remove(spec.key)?.close();
      _cancelledDownloads.remove(spec.key);
    });
    return _downloads[spec.key] = future;
  }

  void _cancelDownloads() {
    for (final key in _downloads.keys) {
      _cancelledDownloads.add(key);
      _downloadClients[key]?.close();
    }
  }

  Future<void> _downloadModel(
      TranslationModelSpec spec, void Function(double)? onProgress) async {
    if (await isDownloaded(spec)) return;
    final dir = await modelDirectory(spec);
    await dir.create(recursive: true);
    final total = spec.bytes;
    var done = 0;
    for (final f in spec.files) {
      if (_cancelledDownloads.contains(spec.key)) {
        throw TranslationModelException("The download was cancelled.");
      }
      final target = File(p.join(dir.path, f.name));
      if (!await target.exists()) {
        final client = _downloadClients[spec.key] = _httpClient();
        await _downloadVerified(client, f, target, (received) {
          onProgress?.call(((done + received) / total).clamp(0.0, 1.0));
        });
      }
      done += f.bytes;
      onProgress?.call((done / total).clamp(0.0, 1.0));
    }
    await (await _completeMarker(spec)).writeAsString(spec.version);
    modelsChanged.value++;
  }

  /// Streams [file] to `[target].part`, hashing as it goes, and renames it
  /// to [target] only when size and SHA-256 match.
  Future<void> _downloadVerified(http.Client client, F file, File target,
      void Function(int received) onProgress) async {
    final part = File("${target.path}.part");
    try {
      final response = await client.send(http.Request("GET", file.url));
      if (response.statusCode != 200) {
        throw TranslationModelException(
            "The language model download failed (HTTP ${response.statusCode}).");
      }
      var received = 0;
      final digestSink = _DigestSink();
      final hasher = sha256.startChunkedConversion(digestSink);
      final out = part.openWrite();
      try {
        await for (final chunk in response.stream) {
          out.add(chunk);
          hasher.add(chunk);
          received += chunk.length;
          onProgress(received);
        }
      } finally {
        await out.close();
      }
      hasher.close();
      if (received != file.bytes ||
          digestSink.value.toString() != file.sha256) {
        throw TranslationModelException(
            "The downloaded language model is damaged. Try again.");
      }
      await part.rename(target.path);
    } on http.ClientException catch (e) {
      throw TranslationModelException(
          "The language model download failed: ${e.message}.");
    } finally {
      if (await part.exists()) await part.delete();
    }
  }

  /// The engine runs one translation at a time; everything that uses it
  /// queues here.
  /// Null while idle. Not a ready-made Future.value(): its callbacks would
  /// run in the zone that made the service (a test's fake clock).
  Future<void>? _engineTail;

  Future<T> _serial<T>(Future<T> Function() work) {
    final previous = _engineTail;
    final result = previous == null ? work() : previous.then((_) => work());
    late final Future<void> tail;
    tail = result.then<void>((_) {}, onError: (_) {}).whenComplete(() {
      if (identical(_engineTail, tail)) _engineTail = null;
    });
    _engineTail = tail;
    return result;
  }

  /// Downloads whatever [models] still need (callers ask the user first).
  Future<void> downloadRoute(List<TranslationModelSpec> models) async {
    for (final spec in await missingModels(models)) {
      await downloadModel(spec);
    }
  }

  /// Translates [text] from [from] into [to], not tied to a message: the
  /// composer (Vommet issue 680 phase 2). Downloads missing models first
  /// (callers ask before that). Throws [TranslationModelException] when no
  /// model covers the pair or a download fails.
  Future<String> translateText(String text, String from, String to) async {
    final models = route(from, to);
    if (models == null) {
      throw TranslationModelException(
          "Can't translate ${translationLanguageName(from)} into ${translationLanguageName(to)} yet.");
    }
    await downloadRoute(models);
    return translateLines(text, models);
  }

  /// Live state for the message [eventId].
  ValueNotifier<TranslationState> stateFor(String eventId) => _states
      .putIfAbsent(eventId, () => ValueNotifier(const TranslationIdle()));

  /// Translates [text] (in [from]) into [targetLanguage], downloading the
  /// models first if needed (callers ask the user before that). Progress and
  /// the result arrive on [stateFor].
  Future<void> translate(String eventId, String text, String from) async {
    final state = stateFor(eventId);
    if (state.value is TranslationRunning ||
        state.value is TranslationDownloading) {
      return;
    }
    final to = targetLanguage;
    final models = route(from, to);
    if (models == null) {
      state.value = TranslationFailed(
          "Can't translate ${translationLanguageName(from)} into ${translationLanguageName(to)} yet.");
      return;
    }

    try {
      final missing = await missingModels(models);
      if (missing.isNotEmpty) {
        _waiting.add(eventId);
        final total = missing.fold(0, (sum, s) => sum + s.bytes);
        var before = 0;
        state.value = const TranslationDownloading(null);
        for (final spec in missing) {
          final base = before;
          await downloadModel(spec, onProgress: (share) {
            final progress = (base + share * spec.bytes) / total;
            downloadProgress.value = progress;
            if (_waiting.contains(eventId)) {
              state.value = TranslationDownloading(progress);
            }
          });
          before += spec.bytes;
          if (!_waiting.contains(eventId)) return; // cancelled meanwhile
        }
        _waiting.remove(eventId);
        downloadProgress.value = null;
      }

      state.value = const TranslationRunning();
      final translated = await translateLines(text, models);
      if (state.value is! TranslationRunning) return; // cancelled
      state.value = TranslationDone(translated, from: from, to: to);
    } on TranslationModelException catch (e) {
      if (!_waiting.contains(eventId) && state.value is TranslationIdle) return;
      state.value = TranslationFailed(e.message);
    } catch (e) {
      debugPrint("Translation failed: $e");
      state.value = const TranslationFailed("Couldn't translate this message.");
    } finally {
      _waiting.remove(eventId);
      if (_waiting.isEmpty) downloadProgress.value = null;
    }
  }

  /// Translates line by line so line breaks survive; blank lines stay blank.
  Future<String> translateLines(
      String text, List<TranslationModelSpec> models) async {
    final lines = text.split("\n");
    final work = [
      for (final l in lines)
        if (l.trim().isNotEmpty) l
    ];
    if (work.isEmpty) return text;
    final out = await _serial(() async {
      for (final spec in models) {
        await engine.load(
            spec.key, spec.config((await modelDirectory(spec)).path));
      }
      return engine.translate(work, [for (final m in models) m.key]);
    });
    var i = 0;
    return [
      for (final l in lines)
        l.trim().isEmpty ? l : (i < out.length ? out[i++] : l)
    ].join("\n");
  }

  void cancel(String eventId) {
    if (_waiting.remove(eventId)) {
      _states[eventId]?.value = const TranslationIdle();
      if (_waiting.isEmpty) _cancelDownloads();
      return;
    }
    // The engine can't stop a running translation; drop its result.
    if (_states[eventId]?.value is TranslationRunning) {
      _states[eventId]?.value = const TranslationIdle();
    }
  }
}

class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
