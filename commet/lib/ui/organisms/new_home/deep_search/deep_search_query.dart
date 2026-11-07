// Vommet (Deep Search, stage 2): the query model. A Deep Search query is
// free text (words and "quoted phrases") plus filter tokens: in: (a room, a
// space or a tag: the sidebar's SearchScope, so both searches share one
// token model), is:dm / is:room, from:, has:, mentions:me, before: and
// after:. Typed tokens become chips once committed (a space after them, or
// Enter); Backspace on an empty text removes the last chip. Pure Dart, so
// it is unit tested; the UI resolves in: / from: values through the
// sidebar's name engine (the parser's resolvers).
import 'package:commet/client/matrix/components/encrypted_search_index/search_index_entry.dart';
import 'package:commet/client/matrix/components/encrypted_search_index/search_index_types.dart';
import 'package:commet/ui/organisms/new_home/deep_search/deep_search_strings.dart';
import 'package:commet/ui/organisms/new_home/new_home_search.dart';

/// has: values.
enum DeepSearchHas { link, image, video, file, voice }

/// Whether a message passes the has: chips [has], from its event content
/// (msgtype, the voice flag) and [body] (links): the server's hits and,
/// without an index (the web), the loaded timelines' messages. Kinds are
/// any-of (as in the index), a link is required on top.
bool deepSearchHasMatches(Set<DeepSearchHas> has, Map<String, Object?> content,
    {String? body}) {
  if (has.isEmpty) return true;
  final raw = content["body"];
  final text = body ?? (raw is String ? raw : "");
  if (has.contains(DeepSearchHas.link) && !_link.hasMatch(text)) return false;
  final kinds = has.where((h) => h != DeepSearchHas.link);
  if (kinds.isEmpty) return true;
  final type = content["msgtype"];
  return kinds.any((h) => switch (h) {
        DeepSearchHas.link => false,
        DeepSearchHas.image => type == "m.image",
        DeepSearchHas.video => type == "m.video",
        DeepSearchHas.file => type == "m.file",
        DeepSearchHas.voice => type == "m.audio" &&
            (content.containsKey("org.matrix.msc3245.voice") ||
                content.containsKey("m.voice")),
      });
}

final _link = RegExp(r"https?://", caseSensitive: false);

/// Whether /search can narrow [has] down server-side: media kinds carry a
/// `url` in their (unencrypted) content, so RoomEventFilter's
/// `contains_url` keeps only those. Links in the text have no `url` key,
/// so has:link alone can't use it (it's post-filtered).
bool deepSearchServerContainsUrl(Set<DeepSearchHas> has) =>
    has.any((h) => h != DeepSearchHas.link);

enum DeepSearchTokenKind { scope, from, has, mentionsMe, before, after }

/// One filter chip.
class DeepSearchToken<S> {
  const DeepSearchToken.scope(SearchScope<S> this.scope)
      : kind = DeepSearchTokenKind.scope,
        userId = null,
        name = null,
        has = null,
        ts = null;

  /// from: a person. [name] is their display name (the chip's text).
  const DeepSearchToken.from(String this.userId, String this.name)
      : kind = DeepSearchTokenKind.from,
        scope = null,
        has = null,
        ts = null;

  const DeepSearchToken.has(DeepSearchHas this.has)
      : kind = DeepSearchTokenKind.has,
        scope = null,
        userId = null,
        name = null,
        ts = null;

  const DeepSearchToken.mentionsMe()
      : kind = DeepSearchTokenKind.mentionsMe,
        scope = null,
        userId = null,
        name = null,
        has = null,
        ts = null;

  /// before: messages sent before [ts] (ms, exclusive). [name] is the
  /// date as shown ("2024-03-05", "2024-03", "today").
  const DeepSearchToken.before(int this.ts, String this.name)
      : kind = DeepSearchTokenKind.before,
        scope = null,
        userId = null,
        has = null;

  /// after: messages sent after [ts] (ms, exclusive).
  const DeepSearchToken.after(int this.ts, String this.name)
      : kind = DeepSearchTokenKind.after,
        scope = null,
        userId = null,
        has = null;

  /// before: the start of [day] (local), for the date picker.
  factory DeepSearchToken.beforeDay(DateTime day) => DeepSearchToken.before(
      DateTime(day.year, day.month, day.day).millisecondsSinceEpoch,
      deepSearchDayLabel(day));

  /// after: the end of [day] (local), for the date picker.
  factory DeepSearchToken.afterDay(DateTime day) => DeepSearchToken.after(
      DateTime(day.year, day.month, day.day + 1).millisecondsSinceEpoch - 1,
      deepSearchDayLabel(day));

  final DeepSearchTokenKind kind;
  final SearchScope<S>? scope;
  final String? userId;
  final String? name;
  final DeepSearchHas? has;
  final int? ts;

  /// The chip's text.
  String get label {
    switch (kind) {
      case DeepSearchTokenKind.scope:
        final s = scope;
        if (s == null) return "";
        if (s.directMessages != null) return s.label;
        return DeepSearchStrings.tokenIn(s.label);
      case DeepSearchTokenKind.from:
        return DeepSearchStrings.tokenFrom(name ?? userId ?? "");
      case DeepSearchTokenKind.has:
        return DeepSearchStrings.tokenHas(has?.name ?? "");
      case DeepSearchTokenKind.mentionsMe:
        return DeepSearchStrings.chipMentionsMe;
      case DeepSearchTokenKind.before:
        return DeepSearchStrings.tokenBefore(name ?? "");
      case DeepSearchTokenKind.after:
        return DeepSearchStrings.tokenAfter(name ?? "");
    }
  }

  /// A stable text for the cache key and recent searches.
  String get key {
    switch (kind) {
      case DeepSearchTokenKind.scope:
        final s = scope;
        if (s == null) return "in:";
        if (s.directMessages != null) {
          return s.directMessages == true ? "is:dm" : "is:room";
        }
        if (s.roomId != null) return "in:room:${s.roomId}";
        if (s.tag != null) return "in:tag:${s.tag}";
        return "in:space:${s.space}";
      case DeepSearchTokenKind.from:
        return "from:$userId";
      case DeepSearchTokenKind.has:
        return "has:${has?.name}";
      case DeepSearchTokenKind.mentionsMe:
        return "mentions:me";
      case DeepSearchTokenKind.before:
        return "before:$ts";
      case DeepSearchTokenKind.after:
        return "after:$ts";
    }
  }

  /// Tokens that can appear once: a second one replaces the first.
  bool get single =>
      kind != DeepSearchTokenKind.from && kind != DeepSearchTokenKind.has;

  @override
  bool operator ==(Object other) =>
      other is DeepSearchToken<S> && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

String _two(int n) => n.toString().padLeft(2, "0");

/// "2024-03-05".
String deepSearchDayLabel(DateTime day) =>
    "${day.year}-${_two(day.month)}-${_two(day.day)}";

/// What the server's /search can be asked (the rest is post-filtered).
class DeepSearchServerFilter {
  const DeepSearchServerFilter({
    required this.searchTerm,
    this.senders = const [],
    this.notSenders = const [],
    this.rooms,
    this.containsUrl = false,
  });

  final String searchTerm;
  final List<String> senders;
  final List<String> notSenders;

  /// null = every room (the server search is account-wide).
  final List<String>? rooms;

  /// Only events with a `url` in their content (media): set for has:
  /// image / video / file / voice ([deepSearchServerContainsUrl]).
  final bool containsUrl;
}

/// A query: the chips plus the typed text.
class DeepSearchQuery<S> {
  const DeepSearchQuery({this.tokens = const [], this.text = ""});

  final List<DeepSearchToken<S>> tokens;

  /// The free text: words and "quoted phrases".
  final String text;

  bool get isEmpty => tokens.isEmpty && text.trim().isEmpty;

  /// The text's quoted phrases, folded ("Book club" → "book club").
  List<String> get phrases => [
        for (final m in _quoted.allMatches(text))
          if (_norm(m.group(1) ?? "").isNotEmpty) _norm(m.group(1) ?? "")
      ];

  /// Every word of the text, phrases' words included, folded and unique.
  List<String> get words {
    final out = <String>[];
    for (final w in searchFold(text.replaceAll('"', " ")).split(_space)) {
      if (w.isNotEmpty && !out.contains(w)) out.add(w);
    }
    return out;
  }

  bool get hasWords => words.isNotEmpty;

  /// Only chips (Decision 15): the index lists them; the server is skipped
  /// (its /search needs words).
  bool get filterOnly => !hasWords && tokens.isNotEmpty;

  /// The cache key: same chips + same folded text = same results.
  String get normalized {
    final keys = [for (final t in tokens) t.key]..sort();
    final p = phrases;
    final loose = [
      for (final w in searchFold(text.replaceAll(_quoted, " ")).split(_space))
        if (w.isNotEmpty) w
    ];
    return [...keys, ...p.map((e) => '"$e"'), ...loose].join("\u0001");
  }

  SearchScope<S>? get scope {
    for (final t in tokens) {
      if (t.kind == DeepSearchTokenKind.scope) return t.scope;
    }
    return null;
  }

  List<String> get fromUserIds => [
        for (final t in tokens)
          if (t.kind == DeepSearchTokenKind.from && t.userId != null)
            t.userId ?? ""
      ];

  Set<DeepSearchHas> get has => {
        for (final t in tokens)
          if (t.kind == DeepSearchTokenKind.has && t.has != null)
            t.has ?? DeepSearchHas.link
      };

  bool get mentionsMe =>
      tokens.any((t) => t.kind == DeepSearchTokenKind.mentionsMe);

  int? get beforeTs => _tsOf(DeepSearchTokenKind.before);
  int? get afterTs => _tsOf(DeepSearchTokenKind.after);

  int? _tsOf(DeepSearchTokenKind kind) {
    for (final t in tokens) {
      if (t.kind == kind) return t.ts;
    }
    return null;
  }

  DeepSearchQuery<S> withText(String next) =>
      DeepSearchQuery(tokens: tokens, text: next);

  /// Adds [token] (a chip tapped or a pick from the in: / from: pickers);
  /// a single-kind token replaces its kind's old one, a duplicate is a
  /// no-op.
  DeepSearchQuery<S> withToken(DeepSearchToken<S> token) {
    if (tokens.contains(token)) return this;
    return DeepSearchQuery(tokens: [
      for (final t in tokens)
        if (!(token.single && t.kind == token.kind)) t,
      token,
    ], text: text);
  }

  DeepSearchQuery<S> withoutToken(DeepSearchToken<S> token) =>
      DeepSearchQuery(tokens: [
        for (final t in tokens)
          if (t != token) t
      ], text: text);

  /// Backspace on an empty text removes the last chip.
  bool get canBackspace => text.isEmpty && tokens.isNotEmpty;

  DeepSearchQuery<S> backspace() => canBackspace
      ? DeepSearchQuery(
          tokens: tokens.sublist(0, tokens.length - 1), text: text)
      : this;

  /// Whether [content] (a hit's text: body, file name) holds every quoted
  /// phrase. The index and the server only require the words, so phrases
  /// are checked here.
  bool matchesPhrases(String content) {
    final p = phrases;
    if (p.isEmpty) return true;
    final folded = _norm(content);
    return p.every(folded.contains);
  }

  /// The index query. [roomIds] is the scope resolved to rooms (null =
  /// every room, see [deepSearchScopeRoomIds]); [ignoredUsers] are never
  /// listed; [myNames] are my display names for mentions:me.
  IndexQuery toIndexQuery(
      {List<String>? roomIds,
      List<String> ignoredUsers = const [],
      List<String> myNames = const []}) {
    final has = this.has;
    return IndexQuery(
      words: words,
      senders: fromUserIds,
      excludeSenders: ignoredUsers,
      roomIds: roomIds,
      requireLink: has.contains(DeepSearchHas.link),
      requireImage: has.contains(DeepSearchHas.image),
      requireVideo: has.contains(DeepSearchHas.video),
      kinds: {
        if (has.contains(DeepSearchHas.file)) SharedContentKind.file,
        if (has.contains(DeepSearchHas.voice)) SharedContentKind.voice,
      },
      mentionsMe: mentionsMe,
      myNames: [for (final n in myNames) n.toLowerCase()],
      beforeTs: beforeTs,
      afterTs: afterTs,
    );
  }

  /// The server's /search filter, or null when the server can't help:
  /// no words (filter-only), or a DMs scope (every DM is indexed).
  /// [rooms] is the scope's rooms the index doesn't cover (null = all).
  DeepSearchServerFilter? toServerFilter(
      {List<String>? rooms, List<String> ignoredUsers = const []}) {
    if (!hasWords) return null;
    if (scope?.directMessages == true) return null;
    if (rooms != null && rooms.isEmpty) return null;
    return DeepSearchServerFilter(
      searchTerm: text.replaceAll('"', " ").trim().replaceAll(_space, " "),
      senders: fromUserIds,
      notSenders: ignoredUsers,
      rooms: rooms,
      containsUrl: deepSearchServerContainsUrl(has),
    );
  }

  static final _quoted = RegExp(r'"([^"]*)"?');
  static final _space = RegExp(r"\s+");
  static String _norm(String s) => searchFold(s).replaceAll(_space, " ").trim();
}

/// The rooms [scope] covers, by [idOf]: null for no scope (every room),
/// the room plus its upgrade chain ([chainOf], oldest last or any order)
/// for a room scope, else the docs the scope takes (a space's subspaces
/// included: a doc's path lists every enclosing space).
List<String>? deepSearchScopeRoomIds<R, S>(
    SearchScope<S>? scope, SearchIndex<R, S> index, String Function(R) idOf,
    {List<String> Function(String roomId)? chainOf}) {
  if (scope == null) return null;
  final roomId = scope.roomId;
  if (roomId != null) {
    final chain = chainOf?.call(roomId) ?? const <String>[];
    return [
      roomId,
      for (final id in chain)
        if (id != roomId) id
    ];
  }
  return [
    for (final doc in index.docs)
      if (scope.takes(doc)) idOf(doc.room)
  ];
}

/// The typed text's committed tokens become chips. A word is committed
/// once whitespace follows it (or on Enter: [parse]'s `commitLast`); a key
/// whose value doesn't resolve stays text.
class DeepSearchParser<S> {
  DeepSearchParser({this.resolveIn, this.resolveFrom, DateTime Function()? now})
      : _now = now ?? DateTime.now;

  /// in: value → a scope (the sidebar engine's best room, space or tag).
  final SearchScope<S>? Function(String value)? resolveIn;

  /// from: value → a person. A full user id ("@mira:example.org")
  /// resolves without it.
  final ({String userId, String name})? Function(String value)? resolveFrom;
  final DateTime Function() _now;

  static final _piece = RegExp(r'(\S*?"[^"]*"?\S*|\S+)(\s*)');

  /// Parses [input] onto [onto]'s chips: committed tokens become chips,
  /// the rest stays the text.
  DeepSearchQuery<S> parse(String input,
      {DeepSearchQuery<S>? onto, bool commitLast = false}) {
    var query = DeepSearchQuery<S>(tokens: onto?.tokens ?? const []);
    final rest = <String>[];
    final pieces = _piece.allMatches(input).toList();
    for (var i = 0; i < pieces.length; i++) {
      final word = pieces[i].group(1) ?? "";
      final committed = commitLast ||
          i < pieces.length - 1 ||
          (pieces[i].group(2) ?? "").isNotEmpty;
      final token = committed ? tokenOf(word) : null;
      if (token != null) {
        query = query.withToken(token);
      } else {
        rest.add(word);
      }
    }
    var text = rest.join(" ");
    // Keep the trailing space the user typed after plain words.
    if (rest.isNotEmpty &&
        pieces.isNotEmpty &&
        (pieces.last.group(2) ?? "").isNotEmpty &&
        !commitLast) {
      text = "$text ";
    }
    return query.withText(text);
  }

  /// The token that [word] ("from:@mira:example.org", "has:link",
  /// 'in:"Book club"') makes, or null.
  DeepSearchToken<S>? tokenOf(String word) {
    final colon = word.indexOf(":");
    if (colon <= 0) return null;
    final key = word.substring(0, colon).toLowerCase();
    var value = word.substring(colon + 1);
    if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
      value = value.substring(1, value.length - 1);
    }
    value = value.trim();
    if (value.isEmpty) return null;
    final lower = value.toLowerCase();
    switch (key) {
      case "in":
        final scope = resolveIn?.call(value);
        return scope == null ? null : DeepSearchToken.scope(scope);
      case "is":
        if (lower == "dm" || lower == "dms") {
          return DeepSearchToken.scope(SearchScope<S>.kind(true));
        }
        if (lower == "room" || lower == "rooms") {
          return DeepSearchToken.scope(SearchScope<S>.kind(false));
        }
        return null;
      case "from":
        final person = resolveFrom?.call(value);
        if (person != null) {
          return DeepSearchToken.from(person.userId, person.name);
        }
        if (value.startsWith("@") && value.contains(":")) {
          return DeepSearchToken.from(value, value);
        }
        return null;
      case "has":
        for (final h in DeepSearchHas.values) {
          if (h.name == lower || "${h.name}s" == lower) {
            return DeepSearchToken.has(h);
          }
        }
        if (lower == "files" || lower == "attachment") {
          return const DeepSearchToken.has(DeepSearchHas.file);
        }
        return null;
      case "mentions":
        return lower == "me" ? const DeepSearchToken.mentionsMe() : null;
      case "before":
        final p = periodOf(lower);
        return p == null
            ? null
            : DeepSearchToken.before(p.start.millisecondsSinceEpoch, value);
      case "after":
        final p = periodOf(lower);
        return p == null
            ? null
            : DeepSearchToken.after(p.end.millisecondsSinceEpoch - 1, value);
    }
    return null;
  }

  /// "2024", "2024-03", "2024-03-05", "today", "yesterday" → the local
  /// period [start, end).
  ({DateTime start, DateTime end})? periodOf(String value) {
    final now = _now();
    if (value == "today" || value == "yesterday") {
      final back = value == "today" ? 0 : 1;
      final start = DateTime(now.year, now.month, now.day - back);
      return (
        start: start,
        end: DateTime(start.year, start.month, start.day + 1)
      );
    }
    final m =
        RegExp(r"^(\d{4})(?:-(\d{1,2})(?:-(\d{1,2}))?)?$").firstMatch(value);
    if (m == null) return null;
    final year = int.tryParse(m.group(1) ?? "");
    if (year == null) return null;
    final month = int.tryParse(m.group(2) ?? "");
    final day = int.tryParse(m.group(3) ?? "");
    if (month != null && (month < 1 || month > 12)) return null;
    if (day != null && (day < 1 || day > 31)) return null;
    if (month == null) {
      return (start: DateTime(year), end: DateTime(year + 1));
    }
    if (day == null) {
      return (start: DateTime(year, month), end: DateTime(year, month + 1));
    }
    final start = DateTime(year, month, day);
    if (start.month != month) return null; // 2024-02-31
    return (start: start, end: DateTime(year, month, day + 1));
  }

  /// The token being typed at the end of [text] ("from:mi"), for the in:
  /// and from: pickers; null when the last word isn't a known key.
  static ({String key, String value})? pendingOf(String text) {
    if (text.isEmpty || text.endsWith(" ")) return null;
    final last = text.split(RegExp(r"\s+")).last;
    final colon = last.indexOf(":");
    if (colon <= 0) return null;
    final key = last.substring(0, colon).toLowerCase();
    const keys = {"in", "from", "has", "is", "mentions", "before", "after"};
    if (!keys.contains(key)) return null;
    return (key: key, value: last.substring(colon + 1).replaceAll('"', ""));
  }
}
