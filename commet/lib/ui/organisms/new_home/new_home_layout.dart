// Vommet: the "New Home" Overview layout (experiment). Pure Dart, so it can be
// unit tested: which cards Overview shows, in what order, and each card's
// settings. Stored in private account data `im.nether.vommet.home_layout`:
//
//   {"cards": [{"id": "recent", "hidden": false, "count": 5, "dms": true,
//               "muted": true, "unreadOnly": false},
//              {"id": "favourites", "hidden": false},
//              {"id": "other_rooms", "hidden": false}]}
//
// Reading is forgiving: unknown fields and unknown card ids (a later Card
// library) are kept as they are and written back untouched; missing or
// broken fields fall back to the defaults; known cards missing from the list
// are added at the end.

/// One card on Overview and its settings.
class HomeCard {
  const HomeCard(
    this.id, {
    this.hidden = false,
    this.count = HomeLayout.defaultCount,
    this.dms = true,
    this.muted = true,
    this.unreadOnly = false,
    this.extra = const {},
  });

  final String id;
  final bool hidden;

  /// Recent activity: how many rooms to show.
  final int count;

  /// Recent activity: include direct messages.
  final bool dms;

  /// Recent activity: include rooms you muted.
  final bool muted;

  /// Recent activity: only rooms with unread messages.
  final bool unreadOnly;

  /// Fields this version doesn't know, kept so they survive a save.
  final Map<String, dynamic> extra;

  bool get known => HomeLayout.knownIds.contains(id);

  HomeCard copyWith({
    bool? hidden,
    int? count,
    bool? dms,
    bool? muted,
    bool? unreadOnly,
  }) =>
      HomeCard(id,
          hidden: hidden ?? this.hidden,
          count: count ?? this.count,
          dms: dms ?? this.dms,
          muted: muted ?? this.muted,
          unreadOnly: unreadOnly ?? this.unreadOnly,
          extra: extra);

  static HomeCard? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json["id"];
    if (id is! String || id.isEmpty) return null;
    final count = json["count"];
    return HomeCard(
      id,
      hidden: _bool(json["hidden"], false),
      count: count is int && count > 0 && count <= HomeLayout.maxCount
          ? count
          : HomeLayout.defaultCount,
      dms: _bool(json["dms"], true),
      muted: _bool(json["muted"], true),
      unreadOnly: _bool(json["unreadOnly"], false),
      extra: {
        for (final e in json.entries)
          if (e.key is String && !_fields.contains(e.key))
            e.key as String: e.value
      },
    );
  }

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{...extra, "id": id, "hidden": hidden};
    if (id == HomeLayout.recent) {
      json["count"] = count;
      json["dms"] = dms;
      json["muted"] = muted;
      json["unreadOnly"] = unreadOnly;
    }
    return json;
  }

  static const _fields = {
    "id",
    "hidden",
    "count",
    "dms",
    "muted",
    "unreadOnly"
  };

  static bool _bool(Object? v, bool fallback) => v is bool ? v : fallback;

  @override
  bool operator ==(Object other) =>
      other is HomeCard &&
      other.id == id &&
      other.hidden == hidden &&
      other.count == count &&
      other.dms == dms &&
      other.muted == muted &&
      other.unreadOnly == unreadOnly;

  @override
  int get hashCode => Object.hash(id, hidden, count, dms, muted, unreadOnly);
}

/// The Overview cards in order, known or not.
class HomeLayout {
  const HomeLayout(this.cards, {this.extra = const {}});

  static const String accountDataKey = "im.nether.vommet.home_layout";

  static const String recent = "recent";
  static const String favourites = "favourites";
  static const String otherRooms = "other_rooms";

  /// The cards this version can show, in their default order.
  static const List<String> knownIds = [recent, favourites, otherRooms];

  /// The counts Recent activity offers.
  static const List<int> counts = [5, 10, 20];
  static const int defaultCount = 5;
  static const int maxCount = 100;

  /// Every card, including ids this version doesn't know (kept, not shown).
  final List<HomeCard> cards;

  /// Top-level fields this version doesn't know.
  final Map<String, dynamic> extra;

  static HomeLayout get defaults =>
      HomeLayout([for (final id in knownIds) HomeCard(id)]);

  static HomeLayout parse(Map<String, dynamic>? content) {
    final list = content?["cards"];
    final cards = <HomeCard>[];
    final seen = <String>{};
    if (list is List) {
      for (final item in list) {
        final card = HomeCard.fromJson(item);
        if (card == null || !seen.add(card.id)) continue;
        cards.add(card);
      }
    }
    for (final id in knownIds) {
      if (seen.add(id)) cards.add(HomeCard(id));
    }
    return HomeLayout(cards, extra: {
      for (final e in (content ?? const {}).entries)
        if (e.key != "cards") e.key: e.value
    });
  }

  Map<String, dynamic> toJson() => {
        ...extra,
        "cards": [for (final c in cards) c.toJson()],
      };

  HomeCard card(String id) =>
      cards.firstWhere((c) => c.id == id, orElse: () => HomeCard(id));

  /// The cards Overview shows, in order.
  List<HomeCard> get visible => [
        for (final c in cards)
          if (c.known && !c.hidden) c
      ];

  /// Known cards the user hid.
  List<HomeCard> get hidden => [
        for (final c in cards)
          if (c.known && c.hidden) c
      ];

  bool canMoveUp(String id) {
    final v = visible;
    final i = v.indexWhere((c) => c.id == id);
    return i > 0;
  }

  bool canMoveDown(String id) {
    final v = visible;
    final i = v.indexWhere((c) => c.id == id);
    return i >= 0 && i < v.length - 1;
  }

  /// Swaps [id] with the visible card above it (-1) or below it (+1). Hidden
  /// and unknown cards keep their places.
  HomeLayout move(String id, int direction) {
    final v = visible;
    final i = v.indexWhere((c) => c.id == id);
    final j = i + direction;
    if (i < 0 || j < 0 || j >= v.length) return this;
    final a = cards.indexWhere((c) => c.id == v[i].id);
    final b = cards.indexWhere((c) => c.id == v[j].id);
    final next = List<HomeCard>.of(cards);
    next[a] = cards[b];
    next[b] = cards[a];
    return HomeLayout(next, extra: extra);
  }

  HomeLayout replace(HomeCard card) =>
      HomeLayout([for (final c in cards) c.id == card.id ? card : c],
          extra: extra);

  HomeLayout hide(String id) => replace(card(id).copyWith(hidden: true));

  /// "Add back": shows every hidden card again, where it was.
  HomeLayout showAll() => HomeLayout(
      [for (final c in cards) c.known ? c.copyWith(hidden: false) : c],
      extra: extra);
}

/// Recent activity: [items] that pass [card]'s filters, newest first (the
/// order Home's Recent Activity has always used), at most [HomeCard.count].
/// Items without any event are left out, like on the old Home.
List<T> recentActivity<T>(
  Iterable<T> items,
  HomeCard card, {
  required DateTime? Function(T item) lastEvent,
  required bool Function(T item) isDirectMessage,
  required bool Function(T item) isMuted,
  required bool Function(T item) isUnread,
}) {
  final result = [
    for (final item in items)
      if (lastEvent(item) != null &&
          (card.dms || !isDirectMessage(item)) &&
          (card.muted || !isMuted(item)) &&
          (!card.unreadOnly || isUnread(item)))
        item
  ];
  // A stable sort, so rooms with the same time keep their order.
  final indexed = [for (var i = 0; i < result.length; i++) (i, result[i])];
  indexed.sort((a, b) {
    final byTime = lastEvent(b.$2)!.compareTo(lastEvent(a.$2)!);
    return byTime != 0 ? byTime : a.$1.compareTo(b.$1);
  });
  return [for (final e in indexed.take(card.count)) e.$2];
}
