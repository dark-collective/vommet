// Vommet (New Home): the side list's search engine. Pure Dart, so it can
// be unit tested, and free of widgets so other searches (Ctrl+K, message
// search pickers) can reuse it. It searches every room and DM of the
// filtered account, not only the shown sections, and ranks the matches in
// groups: NAME (a DM's or room's name, prefix before contains, then
// newest), IN <space> (rooms in a space whose name matches), TAGGED, TOPIC
// (with a snippet) and at most three SPACES to open. A room shows once, in
// its best group. A scope token (a space, a tag, or DMs / Rooms) narrows
// the search; a space scope has a breadcrumb that widens it again.

/// [text] lowercased with common accents dropped ("Café" → "cafe"), one
/// code unit per code unit, so a match's place in it is its place in
/// [text].
String searchFold(String text) {
  final out = StringBuffer();
  for (final unit in text.codeUnits) {
    final char = String.fromCharCode(unit);
    final folded = _accents[char];
    if (folded != null) {
      out.write(folded);
      continue;
    }
    final lower = char.toLowerCase();
    out.write(lower.length == 1 ? lower : char);
  }
  return out.toString();
}

const Map<String, String> _accents = {
  "à": "a", "á": "a", "â": "a", "ã": "a", "ä": "a", "å": "a", "ā": "a", //
  "ă": "a", "ą": "a", "À": "a", "Á": "a", "Â": "a", "Ã": "a", "Ä": "a",
  "Å": "a", "Ā": "a", "Ă": "a", "Ą": "a", "ç": "c", "ć": "c", "č": "c",
  "Ç": "c", "Ć": "c", "Č": "c", "ď": "d", "Ď": "d", "đ": "d", "Đ": "d",
  "è": "e", "é": "e", "ê": "e", "ë": "e", "ē": "e", "ė": "e", "ę": "e",
  "ě": "e", "È": "e", "É": "e", "Ê": "e", "Ë": "e", "Ē": "e", "Ė": "e",
  "Ę": "e", "Ě": "e", "ğ": "g", "Ğ": "g", "ì": "i", "í": "i", "î": "i",
  "ï": "i", "ī": "i", "į": "i", "ı": "i", "Ì": "i", "Í": "i", "Î": "i",
  "Ï": "i", "Ī": "i", "Į": "i", "İ": "i", "ł": "l", "Ł": "l", "ľ": "l",
  "Ľ": "l", "ñ": "n", "ń": "n", "ň": "n", "Ñ": "n", "Ń": "n", "Ň": "n",
  "ò": "o", "ó": "o", "ô": "o", "õ": "o", "ö": "o", "ø": "o", "ō": "o",
  "ő": "o", "Ò": "o", "Ó": "o", "Ô": "o", "Õ": "o", "Ö": "o", "Ø": "o",
  "Ō": "o", "Ő": "o", "ř": "r", "Ř": "r", "ś": "s", "š": "s", "ş": "s",
  "Ś": "s", "Š": "s", "Ş": "s", "ť": "t", "ţ": "t", "Ť": "t", "Ţ": "t",
  "ù": "u", "ú": "u", "û": "u", "ü": "u", "ū": "u", "ů": "u", "ű": "u",
  "ų": "u", "Ù": "u", "Ú": "u", "Û": "u", "Ü": "u", "Ū": "u", "Ů": "u",
  "Ű": "u", "Ų": "u", "ý": "y", "ÿ": "y", "Ý": "y", "Ÿ": "y", "ź": "z",
  "ż": "z", "ž": "z", "Ź": "z", "Ż": "z", "Ž": "z",
};

/// How long a topic is searched (and how much of it is kept).
const int searchTopicLength = 300;

/// How well [text] (folded) matches [query] (folded): 0 at its start, 1
/// at a word's start, 2 inside a word, null not at all.
int? matchRank(String text, String query) {
  if (query.isEmpty) return null;
  var at = text.indexOf(query);
  if (at < 0) return null;
  if (at == 0) return 0;
  while (at > 0) {
    if (!_isWordChar(text.codeUnitAt(at - 1))) return 1;
    at = text.indexOf(query, at + 1);
  }
  return 2;
}

bool _isWordChar(int unit) =>
    (unit >= 0x30 && unit <= 0x39) ||
    (unit >= 0x61 && unit <= 0x7a) ||
    (unit >= 0x41 && unit <= 0x5a) ||
    unit > 0x7f;

/// [items] whose [name] matches [query]: best match first (see
/// [matchRank]), then newest ([last]), then name. The name ranking every
/// search here shares.
List<T> rankByName<T>(Iterable<T> items, String query,
    {required String Function(T item) name,
    String? Function(T item)? alias,
    DateTime? Function(T item)? last}) {
  final q = searchFold(query.trim());
  final ranked = <(int, T)>[];
  for (final item in items) {
    final rank = _bestRank(searchFold(name(item)), alias?.call(item), q);
    if (rank != null) ranked.add((rank, item));
  }
  ranked.sort((a, b) {
    final byRank = a.$1.compareTo(b.$1);
    if (byRank != 0) return byRank;
    final byTime = _newer(last?.call(a.$2), last?.call(b.$2));
    if (byTime != 0) return byTime;
    return searchFold(name(a.$2)).compareTo(searchFold(name(b.$2)));
  });
  return [for (final (_, item) in ranked) item];
}

int? _bestRank(String name, String? alias, String q) {
  final a = matchRank(name, q);
  final b = alias == null ? null : matchRank(searchFold(alias), q);
  if (a == null) return b;
  if (b == null) return a;
  return a < b ? a : b;
}

int _newer(DateTime? a, DateTime? b) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  return b.compareTo(a);
}

/// One room as search sees it, built once per index update.
class SearchDoc<R, S> {
  SearchDoc({
    required this.room,
    required this.name,
    this.partner,
    this.path = const [],
    this.pathNames = const [],
    this.tags = const [],
    this.tagNames = const [],
    String topic = "",
    this.isDirectMessage = false,
    this.last,
  })  : topic = _topic(topic),
        foldedName = searchFold(name),
        foldedPartner = partner == null ? null : searchFold(partner),
        foldedPath = [for (final n in pathNames) searchFold(n)],
        foldedTags = [for (final n in tagNames) searchFold(n)],
        foldedTopic = searchFold(_topic(topic));

  /// One line, at most [searchTopicLength] long.
  static String _topic(String topic) {
    final line = topic.replaceAll(_spaces, " ").trim();
    return line.length > searchTopicLength
        ? line.substring(0, searchTopicLength)
        : line;
  }

  static final RegExp _spaces = RegExp(r"\s+");

  final R room;
  final String name;

  /// A DM's other person's id.
  final String? partner;

  /// The room's spaces, outermost first (its one space path).
  final List<S> path;
  final List<String> pathNames;

  /// Your tags on it (`u.Work`) and their names ("Work").
  final List<String> tags;
  final List<String> tagNames;

  /// Its topic as plain text on one line, at most [searchTopicLength]
  /// long.
  final String topic;
  final bool isDirectMessage;
  final DateTime? last;

  final String foldedName;
  final String? foldedPartner;
  final List<String> foldedPath;
  final List<String> foldedTags;
  final String foldedTopic;
}

/// A space as search sees it: its name and path (outermost first, itself
/// last).
class SearchSpace<S> {
  SearchSpace(this.space, this.name, this.path, {this.parentName})
      : foldedName = searchFold(name);
  final S space;
  final String name;
  final List<S> path;

  /// Its parent's name, shown when two spaces share [name].
  final String? parentName;
  final String foldedName;
}

/// What narrows a search: a space (and its subspaces), a tag, or a kind
/// (direct messages or rooms). Shown as a token in the search field.
class SearchScope<S> {
  const SearchScope.space(S this.space, this.path, this.label)
      : tag = null,
        directMessages = null,
        roomId = null;
  const SearchScope.tag(String this.tag, this.label)
      : space = null,
        path = const [],
        directMessages = null,
        roomId = null;
  const SearchScope.kind(bool this.directMessages)
      : space = null,
        tag = null,
        path = const [],
        roomId = null,
        label = directMessages ? "DMs" : "Rooms";

  /// Deep Search's `in: #room` token: one room (message search only).
  /// It doesn't narrow the name search ([takes] keeps every room); Deep
  /// Search resolves it to the room (and its upgrade chain) itself.
  const SearchScope.room(String this.roomId, this.label)
      : space = null,
        tag = null,
        path = const [],
        directMessages = null;

  final S? space;

  /// [space]'s path, outermost first, itself last: the breadcrumb.
  final List<S> path;
  final String? tag;
  final bool? directMessages;
  final String? roomId;

  /// The token's text.
  final String label;

  bool takes<R>(SearchDoc<R, S> doc) {
    if (space != null) return doc.path.contains(space);
    if (tag != null) return doc.tags.contains(tag);
    if (directMessages != null) return doc.isDirectMessage == directMessages;
    return true;
  }

  @override
  bool operator ==(Object other) =>
      other is SearchScope<S> &&
      other.space == space &&
      other.tag == tag &&
      other.directMessages == directMessages &&
      other.roomId == roomId;

  @override
  int get hashCode => Object.hash(space, tag, directMessages, roomId);
}

/// A matched room and where its text matched (for the highlight).
class SearchHit<R> {
  const SearchHit(this.room, {this.start = -1, this.end = -1, this.snippet});
  final R room;

  /// The match in the room's name, or -1 when it matched elsewhere.
  final int start;
  final int end;

  /// TOPIC: the topic around the match, with the match's place in it.
  final ({String text, int start, int end})? snippet;
}

/// IN <space> or TAGGED: the rooms of one space or tag.
class SearchGroup<R, K> {
  const SearchGroup(this.key, this.label, this.hits);
  final K key;

  /// "Nether › Software Development", or a tag's name.
  final String label;
  final List<SearchHit<R>> hits;
}

/// A search's results, best group first.
class SearchResults<R, S> {
  const SearchResults({
    this.names = const [],
    this.inSpaces = const [],
    this.tagged = const [],
    this.topics = const [],
    this.spaces = const [],
    this.directMessages = 0,
    this.rooms = 0,
    this.spaceChips = const [],
    this.tagChips = const [],
  });

  final List<SearchHit<R>> names;
  final List<SearchGroup<R, S>> inSpaces;
  final List<SearchGroup<R, String>> tagged;
  final List<SearchHit<R>> topics;

  /// At most [SearchIndex.maxSpaces] spaces to open.
  final List<SearchSpace<S>> spaces;

  /// The chips: DMs and Rooms counts, matched spaces and tags.
  final int directMessages;
  final int rooms;
  final List<(SearchSpace<S>, int)> spaceChips;
  final List<(String tag, String name, int)> tagChips;

  bool get isEmpty =>
      names.isEmpty &&
      inSpaces.isEmpty &&
      tagged.isEmpty &&
      topics.isEmpty &&
      spaces.isEmpty;

  /// The rooms in the order shown, [shownIn] of each group (the rest are
  /// behind "Show N more" until [expanded] has the group's key): for
  /// Enter and Alt+Up/Down.
  List<R> order({int shownIn = 3, Set<Object> expanded = const {}}) => [
        for (final hit in names) hit.room,
        for (final group in inSpaces)
          for (final hit in group.hits
              .take(expanded.contains(group.key) ? group.hits.length : shownIn))
            hit.room,
        for (final group in tagged)
          for (final hit in group.hits
              .take(expanded.contains(group.key) ? group.hits.length : shownIn))
            hit.room,
        for (final hit in topics
            .take(expanded.contains(topicsKey) ? topics.length : shownIn))
          hit.room,
      ];

  /// The TOPIC group's key in [order]'s expanded.
  static const String topicsKey = "\u0000topics";
}

/// Every room and space search looks at, built once per room, space or tag
/// change (not per keystroke).
class SearchIndex<R, S> {
  SearchIndex(this.docs, this.spaces);

  final List<SearchDoc<R, S>> docs;
  final List<SearchSpace<S>> spaces;

  static const int maxSpaces = 3;

  late final Map<R, SearchDoc<R, S>> _byRoom = Map.identity()
    ..addAll({for (final d in docs) d.room: d});

  /// [room]'s doc, or null when search leaves it out.
  SearchDoc<R, S>? docOf(R room) => _byRoom[room];

  /// A space's [SearchSpace], or null.
  SearchSpace<S>? spaceOf(S space) {
    for (final s in spaces) {
      if (s.space == space) return s;
    }
    return null;
  }

  /// The space's label, with its parent when another space has the same
  /// name ("Infra · Nether").
  String spaceLabel(SearchSpace<S> space) {
    final same = spaces.where((s) => s.foldedName == space.foldedName).length;
    return same > 1 && space.parentName != null
        ? "${space.name} · ${space.parentName}"
        : space.name;
  }

  /// The rooms matching [query] within [scope]. With a scope and no query,
  /// every room in it, newest first.
  SearchResults<R, S> search(String query, {SearchScope<S>? scope}) {
    final q = searchFold(query.trim());
    final inScope = [
      for (final doc in docs)
        if (scope == null || scope.takes(doc)) doc
    ];
    if (q.isEmpty) {
      if (scope == null) return const SearchResults();
      final all = [...inScope]..sort((a, b) => _newer(a.last, b.last));
      return SearchResults(
        names: [for (final d in all) SearchHit(d.room)],
        directMessages: all.where((d) => d.isDirectMessage).length,
        rooms: all.where((d) => !d.isDirectMessage).length,
        spaceChips: _subspaceChips(scope, all),
      );
    }

    final names = <(int, SearchDoc<R, S>, int)>[];
    final bySpace = <S, (int, List<SearchDoc<R, S>>)>{};
    final byTag = <String, (String, List<SearchDoc<R, S>>)>{};
    final topics = <(SearchDoc<R, S>, int)>[];
    final matched = <SearchDoc<R, S>>[];
    for (final doc in inScope) {
      final nameRank = matchRank(doc.foldedName, q);
      final partnerRank =
          doc.foldedPartner == null ? null : matchRank(doc.foldedPartner!, q);
      if (nameRank != null || partnerRank != null) {
        final rank = nameRank == null
            ? partnerRank!
            : partnerRank == null
                ? nameRank
                : (nameRank < partnerRank ? nameRank : partnerRank);
        names.add(
            (rank, doc, nameRank == null ? -1 : doc.foldedName.indexOf(q)));
        matched.add(doc);
        continue;
      }
      // The deepest of its spaces whose name matches (below the scope).
      var spaceAt = -1;
      final from =
          scope?.space == null ? 0 : doc.path.indexOf(scope!.space as S) + 1;
      for (var i = doc.path.length - 1; i >= from; i--) {
        if (doc.foldedPath[i].contains(q)) {
          spaceAt = i;
          break;
        }
      }
      if (spaceAt >= 0) {
        final space = doc.path[spaceAt];
        final entry = bySpace[space] ?? (spaceAt, <SearchDoc<R, S>>[]);
        entry.$2.add(doc);
        bySpace[space] = entry;
        matched.add(doc);
        continue;
      }
      var tagAt = -1;
      for (var i = 0; i < doc.tags.length; i++) {
        if (doc.foldedTags[i].contains(q)) {
          tagAt = i;
          break;
        }
      }
      if (tagAt >= 0) {
        final tag = doc.tags[tagAt];
        final entry = byTag[tag] ?? (doc.tagNames[tagAt], <SearchDoc<R, S>>[]);
        entry.$2.add(doc);
        byTag[tag] = entry;
        matched.add(doc);
        continue;
      }
      final at = doc.foldedTopic.indexOf(q);
      if (at >= 0) {
        topics.add((doc, at));
        matched.add(doc);
      }
    }

    names.sort((a, b) {
      final byRank = a.$1.compareTo(b.$1);
      if (byRank != 0) return byRank;
      final byTime = _newer(a.$2.last, b.$2.last);
      return byTime != 0 ? byTime : a.$2.foldedName.compareTo(b.$2.foldedName);
    });
    List<SearchHit<R>> newest(List<SearchDoc<R, S>> list) => [
          for (final d in list..sort((a, b) => _newer(a.last, b.last)))
            SearchHit(d.room)
        ];

    final spaceGroups = [
      for (final MapEntry(key: space, value: (depth, list)) in bySpace.entries)
        (
          depth,
          list,
          SearchGroup<R, S>(
              space, _pathLabel(list.first, depth, scope), newest(list))
        )
    ]..sort((a, b) {
        // Best (the most recently active) group first.
        return _newer(a.$2.first.last, b.$2.first.last);
      });

    final tagGroups = [
      for (final MapEntry(key: tag, value: (name, list)) in byTag.entries)
        SearchGroup<R, String>(tag, name, newest(list))
    ]..sort((a, b) => searchFold(a.label).compareTo(searchFold(b.label)));

    topics.sort((a, b) => _newer(a.$1.last, b.$1.last));

    final spaces = [
      for (final s in this.spaces)
        if (matchRank(s.foldedName, q) case final rank?)
          if (scope?.space == null || s.path.contains(scope!.space)) (rank, s)
    ]..sort((a, b) => a.$1.compareTo(b.$1));

    final tagNames = <String, String>{};
    final tagCounts = <String, int>{};
    for (final doc in matched) {
      for (var i = 0; i < doc.tags.length; i++) {
        if (doc.foldedTags[i].contains(q)) {
          tagNames[doc.tags[i]] = doc.tagNames[i];
          tagCounts[doc.tags[i]] = (tagCounts[doc.tags[i]] ?? 0) + 1;
        }
      }
    }

    return SearchResults(
      names: [
        for (final (_, doc, at) in names)
          SearchHit(doc.room, start: at, end: at < 0 ? -1 : at + q.length)
      ],
      inSpaces: [for (final (_, _, group) in spaceGroups) group],
      tagged: tagGroups,
      topics: [
        for (final (doc, at) in topics)
          SearchHit(doc.room, snippet: topicSnippet(doc.topic, at, q.length))
      ],
      spaces: [for (final (_, s) in spaces.take(maxSpaces)) s],
      directMessages: matched.where((d) => d.isDirectMessage).length,
      rooms: matched.where((d) => !d.isDirectMessage).length,
      spaceChips: [
        for (final (_, s) in spaces)
          (s, docs.where((d) => d.path.contains(s.space)).length)
      ],
      tagChips: [
        for (final tag in tagCounts.keys) (tag, tagNames[tag]!, tagCounts[tag]!)
      ],
    );
  }

  /// "Nether › Software Development" down to [depth]; relative to a scoped
  /// space, only what's below it.
  String _pathLabel(SearchDoc<R, S> doc, int depth, SearchScope<S>? scope) {
    final from =
        scope?.space == null ? 0 : doc.path.indexOf(scope!.space as S) + 1;
    return doc.pathNames.sublist(from, depth + 1).join(" › ");
  }

  /// Within a space scope: its subspaces that hold rooms, to narrow it.
  List<(SearchSpace<S>, int)> _subspaceChips(
      SearchScope<S> scope, List<SearchDoc<R, S>> docs) {
    final space = scope.space;
    if (space == null) return const [];
    final counts = <S, int>{};
    for (final doc in docs) {
      final at = doc.path.indexOf(space);
      if (at >= 0 && at + 1 < doc.path.length) {
        counts[doc.path[at + 1]] = (counts[doc.path[at + 1]] ?? 0) + 1;
      }
    }
    return [
      for (final MapEntry(:key, :value) in counts.entries)
        if (spaceOf(key) case final s?) (s, value)
    ];
  }
}

/// The topic around a match at [at] ([length] long): up to 30 characters
/// before it and 120 in all, with "…" where it was cut, and the match's
/// place in the snippet.
({String text, int start, int end}) topicSnippet(
    String topic, int at, int length) {
  const before = 30;
  const total = 120;
  final from = at > before ? at - before : 0;
  final to = from + total < topic.length ? from + total : topic.length;
  final lead = from > 0 ? "…" : "";
  final tail = to < topic.length ? "…" : "";
  final start = lead.length + at - from;
  return (
    text: "$lead${topic.substring(from, to)}$tail",
    start: start,
    end: start + length,
  );
}
