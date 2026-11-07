// Vommet: spellcheck for the message box on desktop (Linux and Windows, where
// the Rust library is loaded). Hunspell dictionaries are downloaded per
// language from the catalog and kept in the app's data folder; every ticked
// language is checked at once. Phones keep their keyboard's own spellcheck.
import 'dart:async';
import 'dart:io';

import 'package:commet/config/platform_utils.dart';
import 'package:commet/config/preferences/bool_preference.dart';
import 'package:commet/config/preferences/string_list_preference.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/rust/frb_generated.dart';
import 'package:commet/utils/spellcheck/spellcheck_catalog.dart';
// Vommet: the native side uses dart:ffi, which web builds don't have.
import 'package:commet/utils/spellcheck/spellcheck_native.dart'
    if (dart.library.js_interop) 'package:commet/utils/spellcheck/spellcheck_native_web.dart';
import 'package:commet/utils/spellcheck/spellcheck_text.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class Spellcheck extends ChangeNotifier {
  Spellcheck._();

  static final Spellcheck instance = Spellcheck._();

  static bool get supported =>
      (PlatformUtils.isLinux || PlatformUtils.isWindows) &&
      RustLib.instance.initialized;

  /// Words that are always right, on top of the personal dictionary.
  static const Set<String> builtInWords = {"Vommet", "Commet"};

  static const int maxSuggestions = 5;

  final BoolPreference enabled =
      BoolPreference("vommet_spellcheck_enabled", defaultValue: true);

  /// Codes of the downloaded languages that are ticked (checked).
  final StringListPreference ticked =
      StringListPreference("vommet_spellcheck_languages", defaultValue: []);

  final StringListPreference personal = StringListPreference(
      "vommet_spellcheck_personal_words",
      defaultValue: []);

  final Map<String, int> _loaded = {};
  final Set<String> _installed = {};
  final Set<String> _failed = {};
  final Map<String, double> _downloads = {};
  Set<String> _personalLower = {};
  Future<void>? _init;
  String? _dir;
  int _busy = 0;
  final List<int> _closeLater = [];

  /// Changes whenever the result of a check could change.
  int generation = 0;

  Set<String> get installed => Set.unmodifiable(_installed);
  bool isTicked(String code) => ticked.value.contains(code);
  bool isLoaded(String code) => _loaded.containsKey(code);
  bool failedToLoad(String code) => _failed.contains(code);

  /// Download progress 0..1 per language code being downloaded.
  Map<String, double> get downloads => Map.unmodifiable(_downloads);

  bool get ready => _init != null;

  /// True when typing in the message box is being checked.
  bool get active => supported && enabled.value && _loaded.isNotEmpty;

  /// A dictionary for the device's language that isn't downloaded yet.
  SpellcheckLanguage? get offer {
    final language = SpellcheckCatalog.forLocale(Platform.localeName) ??
        SpellcheckCatalog.forLocale(
            PlatformDispatcher.instance.locale.toLanguageTag());
    if (language == null || _installed.contains(language.code)) return null;
    return language;
  }

  Future<void> ensureInit() {
    if (!supported) return Future.value();
    return _init ??= _doInit();
  }

  Future<void> _doInit() async {
    try {
      final support = await getApplicationSupportDirectory();
      _dir = p.join(support.path, "spellcheck");
      final dir = Directory(_dir!);
      if (await dir.exists()) {
        await for (final f in dir.list()) {
          if (f is File && f.path.endsWith(".dic")) {
            final code = p.basenameWithoutExtension(f.path);
            if (await File(_aff(code)).exists()) _installed.add(code);
          }
        }
      }
      _refreshPersonal();
      await SpellcheckNative.load();
      _changed();
      await Future.wait([
        for (final code in ticked.value)
          if (_installed.contains(code)) _load(code)
      ]);
    } catch (e, s) {
      Log.onError(e, s, content: "Spellcheck failed to start");
    }
  }

  String _aff(String code) => p.join(_dir!, "$code.aff");
  String _dic(String code) => p.join(_dir!, "$code.dic");

  void _changed() {
    generation++;
    _cache = null;
    notifyListeners();
  }

  /// Re-checks open message boxes (e.g. after "Ignore in this message").
  void refresh() => _changed();

  void _refreshPersonal() {
    _personalLower = {for (final w in personal.value) w.toLowerCase()};
  }

  Future<void> _load(String code) async {
    if (_loaded.containsKey(code)) return;
    int address;
    try {
      address = await SpellcheckNative.openFiles(_aff(code), _dic(code));
    } catch (e, s) {
      Log.onError(e, s, content: "Spellcheck: couldn't open $code");
      address = 0;
    }
    if (address == 0) {
      _failed.add(code);
      Log.w("Spellcheck: couldn't read the $code dictionary");
    } else if (!isTicked(code) || _loaded.containsKey(code)) {
      // Unticked (or loaded twice) while it was opening.
      _close(address);
    } else {
      _failed.remove(code);
      _loaded[code] = address;
    }
    _changed();
  }

  void _unload(String code) {
    final address = _loaded.remove(code);
    if (address != null) _close(address);
    _changed();
  }

  void _close(int address) {
    // A suggestion lookup may still be reading it on another isolate.
    if (_busy > 0) {
      _closeLater.add(address);
    } else {
      SpellcheckNative.instance?.close(address);
    }
  }

  Future<void> setTicked(String code, bool value) async {
    final list = ticked.value.where((c) => c != code).toList();
    if (value) list.add(code);
    await ticked.set(list);
    if (value && _installed.contains(code)) {
      await _load(code);
    } else {
      _unload(code);
    }
  }

  /// Downloads a dictionary and ticks it. Throws if the download fails.
  Future<void> download(SpellcheckLanguage language) async {
    await ensureInit();
    if (_dir == null || _downloads.containsKey(language.code)) return;
    _downloads[language.code] = 0;
    notifyListeners();
    final client = http.Client();
    try {
      await Directory(_dir!).create(recursive: true);
      var done = 0;
      Future<void> fetch(Uri url, int size, String path) async {
        final response = await client.send(http.Request("GET", url));
        if (response.statusCode != 200) {
          throw HttpException("HTTP ${response.statusCode}", uri: url);
        }
        final part = File("$path.part");
        final sink = part.openWrite();
        var got = 0;
        try {
          await for (final chunk in response.stream) {
            got += chunk.length;
            if (got > size) throw HttpException("Too large", uri: url);
            sink.add(chunk);
            _downloads[language.code] = (done + got) / language.bytes;
            notifyListeners();
          }
        } finally {
          await sink.close();
        }
        if (got != size) {
          await part.delete();
          throw HttpException("Got $got of $size bytes", uri: url);
        }
        await part.rename(path);
        done += size;
      }

      await fetch(language.affUrl, language.affBytes, _aff(language.code));
      await fetch(language.dicUrl, language.dicBytes, _dic(language.code));
      _installed.add(language.code);
      _downloads.remove(language.code);
      await setTicked(language.code, true);
    } finally {
      client.close();
      if (_downloads.remove(language.code) != null) notifyListeners();
    }
  }

  Future<void> remove(String code) async {
    await setTicked(code, false);
    _installed.remove(code);
    _failed.remove(code);
    for (final path in [_aff(code), _dic(code)]) {
      try {
        await File(path).delete();
      } catch (_) {}
    }
    _changed();
  }

  Future<void> addWord(String word) async {
    await personal.set({...personal.value, word}.toList()..sort());
    _refreshPersonal();
    _changed();
  }

  Future<void> removeWord(String word) async {
    await personal.set(personal.value.where((w) => w != word).toList());
    _refreshPersonal();
    _changed();
  }

  bool isCorrect(String word) {
    if (builtInWords.contains(word)) return true;
    if (_personalLower.contains(word.toLowerCase())) return true;
    final native = SpellcheckNative.instance;
    if (native == null || _loaded.isEmpty) return true;
    for (final d in _loaded.values) {
      // -1 (couldn't check) counts as correct: never flag what we can't judge.
      if (native.check(d, word) != 0) return true;
    }
    return false;
  }

  (String, int, Set<String>, List<TextRange>)? _cache;

  /// Misspelled words in [text], skipping words in [ignored].
  List<TextRange> misspelled(String text, {Set<String> ignored = const {}}) {
    if (!active) return const [];
    final cache = _cache;
    if (cache != null &&
        cache.$1 == text &&
        cache.$2 == generation &&
        setEquals(cache.$3, ignored)) {
      return cache.$4;
    }
    final result = [
      for (final r in SpellcheckText.words(text))
        if (!ignored.contains(r.textInside(text)) &&
            !isCorrect(r.textInside(text)))
          r
    ];
    _cache = (text, generation, {...ignored}, result);
    return result;
  }

  /// Suggestions for [word] from all ticked dictionaries, best first.
  Future<List<String>> suggest(String word) async {
    if (!active) return const [];
    _busy++;
    try {
      final lists = await SpellcheckNative.suggestIn(
          _loaded.values.toList(), word, maxSuggestions);
      final result = <String>[];
      for (var i = 0; result.length < maxSuggestions; i++) {
        var any = false;
        for (final list in lists) {
          if (i < list.length) {
            any = true;
            if (!result.contains(list[i])) result.add(list[i]);
          }
        }
        if (!any) break;
      }
      return result.take(maxSuggestions).toList();
    } catch (e, s) {
      Log.onError(e, s, content: "Spellcheck suggestions failed");
      return const [];
    } finally {
      _busy--;
      if (_busy == 0) {
        for (final address in _closeLater) {
          SpellcheckNative.instance?.close(address);
        }
        _closeLater.clear();
      }
    }
  }
}

/// The message box's [span] with misspelled words underlined. The word still
/// being typed is left alone until the caret leaves it.
TextSpan markMisspelled(TextEditingValue value, TextSpan span,
    BuildContext context, Set<String> ignored) {
  final spellcheck = Spellcheck.instance;
  if (!spellcheck.active) return span;
  final ranges = SpellcheckText.withoutWordBeingTyped(
      spellcheck.misspelled(value.text, ignored: ignored), value.selection);
  return SpellcheckText.mark(
      span,
      ranges,
      TextStyle(
          decoration: TextDecoration.underline,
          decorationStyle: TextDecorationStyle.wavy,
          decorationColor: Theme.of(context).colorScheme.error,
          decorationThickness: 1.5));
}
