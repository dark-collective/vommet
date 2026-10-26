import 'dart:convert';

import 'package:commet/config/preferences/bool_preference.dart';
import 'package:commet/config/preferences/string_preference.dart';
import 'package:commet/utils/translation/message_translation.dart';
import 'package:commet/utils/translation/model_spec.dart';

// Translating what you write (Vommet issue 680 phase 2): the composer's
// translate button and the room translation mode's "Translate what I
// write" both go through here. The UI is in
// `ui/molecules/composer_translation.dart`.

/// The language most of [texts] (newest first) are in, counting reliable
/// guesses among the first [limit] non-blank ones; ties go to the newest.
/// Null when none of them can be told.
String? dominantLanguage(
    Iterable<String> texts, String? Function(String) detect,
    {int limit = 10}) {
  final counts = <String, int>{};
  String? newest;
  for (final text in texts.where((t) => t.trim().isNotEmpty).take(limit)) {
    final code = detect(text);
    if (code == null) continue;
    newest ??= code;
    counts[code] = (counts[code] ?? 0) + 1;
  }
  if (newest == null) return null;
  var best = newest;
  for (final e in counts.entries) {
    if (e.value > counts[best]!) best = e.key;
  }
  return best;
}

/// A JSON value kept in one string preference.
class JsonPreference {
  JsonPreference(String key, {required String empty})
      : _pref = StringPreference(key, defaultValue: empty),
        _empty = empty;

  final StringPreference _pref;
  final String _empty;

  dynamic read() {
    try {
      return jsonDecode(_pref.value);
    } catch (_) {
      return jsonDecode(_empty);
    }
  }

  Future<void> write(Object value) => _pref.set(jsonEncode(value));
}

/// The composer button's settings: on or off, and the language picked per
/// room ("Translate into"), remembered until changed.
class ComposerTranslationPrefs {
  ComposerTranslationPrefs._();

  static final ComposerTranslationPrefs instance = ComposerTranslationPrefs._();

  /// Settings › App › Translation: "Translate button when writing". Off
  /// until you turn it on; then it shows in every room.
  static final BoolPreference buttonPreference =
      BoolPreference("message_translation_compose_button", defaultValue: false);

  /// {"rooms": {roomId: code}, "recent": [code, ...]} (newest first).
  final JsonPreference _store =
      JsonPreference("message_translation_compose", empty: "{}");

  static const maxRecent = 8;

  Map<String, dynamic> _read() {
    final v = _store.read();
    return v is Map<String, dynamic> ? v : <String, dynamic>{};
  }

  /// The language picked for [roomId], if any.
  String? targetFor(String roomId) {
    final rooms = _read()["rooms"];
    final code = rooms is Map ? rooms[roomId] : null;
    return code is String && translationLanguageNames.containsKey(code)
        ? code
        : null;
  }

  /// Languages picked before, newest first.
  List<String> get recentLanguages {
    final recent = _read()["recent"];
    return recent is List ? recent.whereType<String>().toList() : [];
  }

  Future<void> setTarget(String roomId, String code) async {
    final data = _read();
    final rooms = Map<String, dynamic>.from(
        data["rooms"] is Map ? data["rooms"] as Map : const {});
    rooms[roomId] = code;
    final recent = [code, ...recentLanguages.where((c) => c != code)]
        .take(maxRecent)
        .toList();
    await _store.write({"rooms": rooms, "recent": recent});
  }
}

/// The languages for the "Translate into" menu: [recent] ones first (in
/// their order), then the rest by name; only those reachable from [from].
List<String> menuLanguages(
    MessageTranslation translation, String from, List<String> recent) {
  final reachable = translation.reachableFrom(from);
  final first = [
    for (final c in recent)
      if (reachable.contains(c)) c
  ];
  return [...first, ...reachable.where((c) => !first.contains(c))];
}

sealed class DraftTranslation {
  const DraftTranslation();
}

/// [text] is [draft] in [to].
class DraftTranslated extends DraftTranslation {
  const DraftTranslated(this.text, {required this.from, required this.to});
  final String text;
  final String from;
  final String to;
}

/// The draft is already in the language; send it as written.
class DraftUnchanged extends DraftTranslation {
  const DraftUnchanged();
}

/// Can't translate it; never send it untranslated without saying so.
class DraftBlocked extends DraftTranslation {
  const DraftBlocked(this.message);
  final String message;
}

/// Translates [draft] into [to], asking [confirmDownload] before missing
/// models download (false or null = don't). [ready] is a translation of this
/// exact draft into [to] already made (the live preview).
Future<DraftTranslation> translateDraft(
  MessageTranslation translation, {
  required String draft,
  required String? to,
  required Future<bool?> Function(
          String from, String to, List<TranslationModelSpec> missing)
      confirmDownload,
  String? ready,
}) async {
  if (draft.trim().isEmpty) return const DraftUnchanged();
  if (to == null) {
    return const DraftBlocked("Pick the language to send in.");
  }
  final from = translation.draftLanguage(draft);
  if (from == to) return const DraftUnchanged();
  if (ready != null) return DraftTranslated(ready, from: from, to: to);
  final models = translation.route(from, to);
  if (models == null) {
    return DraftBlocked(
        "Can't translate ${translationLanguageName(from)} into ${translationLanguageName(to)} yet.");
  }
  final missing = await translation.missingModels(models);
  if (missing.isNotEmpty && await confirmDownload(from, to, missing) != true) {
    return const DraftBlocked(
        "The language model isn't downloaded, so nothing was translated.");
  }
  try {
    final text = await translation.translateText(draft, from, to);
    return DraftTranslated(text, from: from, to: to);
  } on TranslationModelException catch (e) {
    return DraftBlocked(e.message);
  } catch (_) {
    return const DraftBlocked("Couldn't translate your message.");
  }
}
