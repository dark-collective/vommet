// Vommet (Deep Search, stage 2): recent searches (Decision 14): the last
// five, on this device only, with Clear and a setting (default on; turning
// it off forgets them). An entry keeps the text and the chips, so tapping
// it runs the same search again.
import 'dart:convert';

import 'package:commet/config/deep_search_setting.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/ui/organisms/new_home/deep_search/deep_search_query.dart';
import 'package:commet/ui/organisms/new_home/new_home_search.dart';

/// One remembered search.
class DeepSearchRecent {
  const DeepSearchRecent({this.text = "", this.tokens = const []});

  final String text;

  /// The chips, encoded (see [DeepSearchRecentStore.encodeToken]).
  final List<Map<String, String>> tokens;

  /// The row's second line: "from: Mira · in: #general · has: file".
  String get summary => [
        for (final t in tokens)
          if ((t["summary"] ?? "").isNotEmpty) t["summary"] ?? ""
      ].join(" · ");

  /// The row's first line: the text, or the summary for a filter-only
  /// search.
  String get title => text.trim().isNotEmpty ? text.trim() : summary;

  Map<String, Object?> toJson() => {"text": text, "tokens": tokens};

  static DeepSearchRecent? fromJson(Object? json) {
    if (json is! Map) return null;
    final text = json["text"];
    final tokens = json["tokens"];
    return DeepSearchRecent(
      text: text is String ? text : "",
      tokens: [
        if (tokens is List)
          for (final t in tokens)
            if (t is Map)
              {
                for (final e in t.entries)
                  if (e.key is String && e.value is String)
                    e.key as String: e.value as String
              }
      ],
    );
  }
}

class DeepSearchRecentStore<S> {
  DeepSearchRecentStore({this.spaceIdOf, this.resolveSpace});

  static const max = 5;

  /// A space's id, to remember an in: space chip.
  final String Function(S space)? spaceIdOf;

  /// The space scope for a remembered space id (null: the space is gone,
  /// the chip is dropped).
  final SearchScope<S>? Function(String spaceId)? resolveSpace;

  bool get enabled => deepSearchRecentPreference.value;

  List<DeepSearchRecent> get entries {
    if (!enabled) return const [];
    final out = <DeepSearchRecent>[];
    for (final raw in deepSearchRecentListPreference.value) {
      try {
        final entry = DeepSearchRecent.fromJson(jsonDecode(raw));
        if (entry != null) out.add(entry);
      } catch (e, s) {
        Log.onError(e, s, content: "Deep Search: bad recent search entry");
      }
    }
    return out;
  }

  /// Remembers [query] (a search that ran: Enter, a result opened). The
  /// same search moves to the top; at most [max] are kept.
  Future<void> remember(DeepSearchQuery<S> query) async {
    if (!enabled || query.isEmpty) return;
    final entry = DeepSearchRecent(text: query.text.trim(), tokens: [
      for (final t in query.tokens)
        if (encodeToken(t) != null) encodeToken(t) ?? const {}
    ]);
    final raw = jsonEncode(entry.toJson());
    final key = _key(entry);
    final kept = [
      raw,
      for (final e in deepSearchRecentListPreference.value)
        if (_keyOfRaw(e) != key) e
    ];
    await deepSearchRecentListPreference
        .set(kept.take(max).toList(growable: false));
  }

  Future<void> remove(DeepSearchRecent entry) async {
    final key = _key(entry);
    await deepSearchRecentListPreference.set([
      for (final e in deepSearchRecentListPreference.value)
        if (_keyOfRaw(e) != key) e
    ]);
  }

  /// "Clear".
  Future<void> clear() => deepSearchRecentListPreference.set(const []);

  /// The setting: off forgets every entry.
  Future<void> setEnabled(bool on) async {
    await deepSearchRecentPreference.set(on);
    if (!on) await clear();
  }

  static String _key(DeepSearchRecent e) => [
        searchFold(e.text.trim()),
        for (final t in e.tokens) "${t["kind"]}=${t["id"]}",
      ].join("\u0001");

  static String? _keyOfRaw(String raw) {
    try {
      final e = DeepSearchRecent.fromJson(jsonDecode(raw));
      return e == null ? null : _key(e);
    } catch (_) {
      return null;
    }
  }

  /// A chip as text fields: kind, id, name (the chip text) and summary.
  Map<String, String>? encodeToken(DeepSearchToken<S> t) {
    String summaryOf(String key, String value) => "$key: $value";
    switch (t.kind) {
      case DeepSearchTokenKind.scope:
        final s = t.scope;
        if (s == null) return null;
        final dm = s.directMessages;
        if (dm != null) {
          return {
            "kind": "is",
            "id": dm ? "dm" : "room",
            "name": s.label,
            "summary": s.label,
          };
        }
        final roomId = s.roomId;
        if (roomId != null) {
          return {
            "kind": "room",
            "id": roomId,
            "name": s.label,
            "summary": summaryOf("in", s.label),
          };
        }
        final tag = s.tag;
        if (tag != null) {
          return {
            "kind": "tag",
            "id": tag,
            "name": s.label,
            "summary": summaryOf("in", s.label),
          };
        }
        final space = s.space;
        final idOf = spaceIdOf;
        if (space == null || idOf == null) return null;
        return {
          "kind": "space",
          "id": idOf(space),
          "name": s.label,
          "summary": summaryOf("in", s.label),
        };
      case DeepSearchTokenKind.from:
        final name = t.name ?? t.userId ?? "";
        return {
          "kind": "from",
          "id": t.userId ?? "",
          "name": name,
          "summary": summaryOf("from", name),
        };
      case DeepSearchTokenKind.has:
        final has = t.has?.name ?? "";
        return {
          "kind": "has",
          "id": has,
          "name": has,
          "summary": summaryOf("has", has),
        };
      case DeepSearchTokenKind.mentionsMe:
        return const {
          "kind": "mentions",
          "id": "me",
          "name": "Mentions me",
          "summary": "mentions: me",
        };
      case DeepSearchTokenKind.before:
      case DeepSearchTokenKind.after:
        final key = t.kind == DeepSearchTokenKind.before ? "before" : "after";
        return {
          "kind": key,
          "id": "${t.ts ?? 0}",
          "name": t.name ?? "",
          "summary": summaryOf(key, t.name ?? ""),
        };
    }
  }

  DeepSearchToken<S>? decodeToken(Map<String, String> m) {
    final id = m["id"] ?? "";
    final name = m["name"] ?? id;
    switch (m["kind"]) {
      case "is":
        return DeepSearchToken.scope(SearchScope<S>.kind(id == "dm"));
      case "room":
        return id.isEmpty
            ? null
            : DeepSearchToken.scope(SearchScope<S>.room(id, name));
      case "tag":
        return id.isEmpty
            ? null
            : DeepSearchToken.scope(SearchScope<S>.tag(id, name));
      case "space":
        final scope = resolveSpace?.call(id);
        return scope == null ? null : DeepSearchToken.scope(scope);
      case "from":
        return id.isEmpty ? null : DeepSearchToken.from(id, name);
      case "has":
        for (final h in DeepSearchHas.values) {
          if (h.name == id) return DeepSearchToken.has(h);
        }
        return null;
      case "mentions":
        return const DeepSearchToken.mentionsMe();
      case "before":
      case "after":
        final ts = int.tryParse(id);
        if (ts == null) return null;
        return m["kind"] == "before"
            ? DeepSearchToken.before(ts, name)
            : DeepSearchToken.after(ts, name);
    }
    return null;
  }

  /// The query a remembered search runs (chips that no longer resolve are
  /// dropped).
  DeepSearchQuery<S> queryOf(DeepSearchRecent entry) {
    var q = DeepSearchQuery<S>(text: entry.text);
    for (final m in entry.tokens) {
      final t = decodeToken(m);
      if (t != null) q = q.withToken(t);
    }
    return q;
  }
}
