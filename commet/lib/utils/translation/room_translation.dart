import 'dart:async';

import 'package:commet/utils/translation/composer_translation.dart';
import 'package:commet/utils/translation/message_translation.dart';
import 'package:commet/utils/translation/model_spec.dart';
import 'package:flutter/foundation.dart';

/// One room's "Translate this room" settings (Vommet issue 680 phase 2).
class RoomTranslationSettings {
  const RoomTranslationSettings(
      {this.on = false, this.from, this.translateWriting = true});

  final bool on;

  /// "Messages are in": picked by you; null = detected.
  final String? from;

  /// "Translate what I write before sending".
  final bool translateWriting;

  static RoomTranslationSettings fromJson(Object? json) {
    if (json is! Map) return const RoomTranslationSettings();
    final from = json["from"];
    return RoomTranslationSettings(
      on: json["on"] == true,
      from: from is String && translationLanguageNames.containsKey(from)
          ? from
          : null,
      translateWriting: json["write"] != false,
    );
  }

  Map<String, Object?> toJson() =>
      {"on": on, if (from != null) "from": from, "write": translateWriting};
}

/// "Translate this room" (Vommet issue 680 phase 2): per-room settings, kept
/// on the device, and the reading side's queue. While it's on, other
/// people's text messages in another language are translated as they're
/// built on screen, one at a time, into your translation language; the
/// models for a language pair are asked for once per room.
class RoomTranslation extends ChangeNotifier {
  RoomTranslation({MessageTranslation? translation})
      : _translation = translation {
    // The master switch and "Languages I read" pause or resume rooms
    // (Vommet issues 820, 821).
    _prefSubs = [
      MessageTranslation.enabledPreference.onChanged
          .listen((_) => notifyListeners()),
      MessageTranslation.readPreference.onChanged
          .listen((_) => notifyListeners()),
    ];
  }

  late final List<StreamSubscription<Object?>> _prefSubs;

  @override
  void dispose() {
    for (final sub in _prefSubs) {
      sub.cancel();
    }
    super.dispose();
  }

  static final RoomTranslation instance = RoomTranslation();

  final MessageTranslation? _translation;
  MessageTranslation get translation =>
      _translation ?? MessageTranslation.instance;

  /// {roomId: {"on": bool, "from": code, "write": bool}}
  final JsonPreference _rooms =
      JsonPreference("message_translation_rooms", empty: "{}");

  bool get supported => translation.supported;

  Map<String, dynamic> _read() {
    final v = _rooms.read();
    return v is Map<String, dynamic> ? v : <String, dynamic>{};
  }

  RoomTranslationSettings settingsFor(String roomId) =>
      RoomTranslationSettings.fromJson(_read()[roomId]);

  bool isOn(String roomId) => settingsFor(roomId).on && supported;

  /// Translating what you write in [roomId] before it's sent.
  bool translatesWriting(String roomId) {
    final s = settingsFor(roomId);
    return s.on && s.translateWriting && supported;
  }

  Future<void> _update(String roomId, RoomTranslationSettings settings) async {
    final rooms = _read();
    rooms[roomId] = settings.toJson();
    await _rooms.write(rooms);
    notifyListeners();
  }

  Future<void> setOn(String roomId, bool on) {
    final s = settingsFor(roomId);
    _pairs.removeWhere((key, _) => key.startsWith("$roomId\u0000"));
    return _update(
        roomId,
        RoomTranslationSettings(
            on: on, from: s.from, translateWriting: s.translateWriting));
  }

  Future<void> setFrom(String roomId, String? from) {
    final s = settingsFor(roomId);
    return _update(
        roomId,
        RoomTranslationSettings(
            on: s.on, from: from, translateWriting: s.translateWriting));
  }

  Future<void> setTranslateWriting(String roomId, bool value) {
    final s = settingsFor(roomId);
    return _update(
        roomId,
        RoomTranslationSettings(
            on: s.on, from: s.from, translateWriting: value));
  }

  /// The language the room's messages are in: the one you picked, else the
  /// most common one in others' recent messages ([detected]).
  String? roomLanguage(String roomId, String? Function() detected) =>
      settingsFor(roomId).from ?? detected();

  /// Whether [roomId] is translated from a language you read (your
  /// translation language or one of "Languages I read"): no offer, no
  /// "Translating from" chip, and the room mode stays idle (Vommet issue
  /// 821). Writing translation is unaffected.
  bool readsRoom(String roomId, String? Function() detected) {
    final from = roomLanguage(roomId, detected);
    return from != null && translation.readsLanguage(from);
  }

  /// Downloads under way for a room's language pair (the header chip).
  final Set<String> downloading = {};

  final Map<String, Future<bool>> _pairs = {};

  /// Whether [from] → [to] can be translated in [roomId] without asking
  /// again: true when the models are there or were just downloaded, false
  /// when you said no (for the rest of the session, or until the mode is
  /// switched off and on). [confirm] returns null when it couldn't ask (its
  /// message is gone); the next message asks then.
  Future<bool> ensureModels(
      String roomId,
      String from,
      String to,
      Future<bool?> Function(
              String from, String to, List<TranslationModelSpec> missing)
          confirm) {
    final key = "$roomId\u0000$from>$to";
    final running = _pairs[key];
    if (running != null) return running;
    final future = () async {
      final models = translation.route(from, to);
      if (models == null) return false;
      final missing = await translation.missingModels(models);
      if (missing.isEmpty) return true;
      final ok = await confirm(from, to, missing);
      if (ok == null) {
        _pairs.remove(key);
        return false;
      }
      if (!ok) return false;
      downloading.add(roomId);
      notifyListeners();
      try {
        await translation.downloadRoute(models);
        return true;
      } catch (e) {
        debugPrint("Translation model download failed: $e");
        return false;
      } finally {
        downloading.remove(roomId);
        notifyListeners();
      }
    }();
    return _pairs[key] = future;
  }

  /// Message keys translated by the room mode (they fold away when it's
  /// switched off).
  final Set<String> _autoKeys = {};

  bool wasAutoTranslated(String key) => _autoKeys.contains(key);

  Future<void> _tail = Future.value();

  /// Queues [text] (message [key], in [from]) for translation into your
  /// language, skipped when [wanted] says it's gone from the screen by its
  /// turn. False when the models aren't there and you said no.
  Future<bool> autoTranslate(
    String roomId,
    String key,
    String text,
    String from, {
    required bool Function() wanted,
    required Future<bool?> Function(
            String from, String to, List<TranslationModelSpec> missing)
        confirm,
  }) async {
    if (!await ensureModels(
        roomId, from, translation.targetLanguage, confirm)) {
      return false;
    }
    final mine = _tail = _tail.then((_) async {
      if (!wanted() || !isOn(roomId)) return;
      if (translation.stateFor(key).value is! TranslationIdle) return;
      _autoKeys.add(key);
      await translation.translate(key, text, from);
    }).catchError((Object e) {
      debugPrint("Room translation failed: $e");
    });
    await mine;
    return true;
  }
}

/// What you wrote before "Translate what I write" sent it in another
/// language, so your own messages show your words (Vommet issue 680 phase
/// 2). Device-only, newest [maxEntries] kept, matched by room and the text
/// that was sent.
class SentTranslations {
  SentTranslations._();

  static final SentTranslations instance = SentTranslations._();

  static const maxEntries = 100;

  /// [[roomId, sent, original, language], ...], oldest first.
  final JsonPreference _store =
      JsonPreference("message_translation_sent", empty: "[]");

  Map<String, ({String original, String language})>? _cache;

  static String _key(String roomId, String sent) =>
      "$roomId\u0000${sent.trim()}";

  Map<String, ({String original, String language})> _entries() {
    final cached = _cache;
    if (cached != null) return cached;
    final result = <String, ({String original, String language})>{};
    final data = _store.read();
    if (data is List) {
      for (final e in data) {
        if (e is List && e.length == 4 && e.every((v) => v is String)) {
          result[_key(e[0] as String, e[1] as String)] =
              (original: e[2] as String, language: e[3] as String);
        }
      }
    }
    return _cache = result;
  }

  /// Forget the in-memory copy (tests).
  @visibleForTesting
  void reload() => _cache = null;

  int get length => _entries().length;

  ({String original, String language})? lookup(String roomId, String sent) =>
      _entries()[_key(roomId, sent)];

  Future<void> remember(String roomId,
      {required String sent,
      required String original,
      required String language}) async {
    final entries = _entries();
    final key = _key(roomId, sent);
    entries.remove(key);
    entries[key] = (original: original, language: language);
    while (entries.length > maxEntries) {
      entries.remove(entries.keys.first);
    }
    await _store.write([
      for (final e in entries.entries)
        [
          e.key.substring(0, e.key.indexOf("\u0000")),
          e.key.substring(e.key.indexOf("\u0000") + 1),
          e.value.original,
          e.value.language,
        ]
    ]);
  }
}
