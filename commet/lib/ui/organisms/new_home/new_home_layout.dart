// Vommet: the "New Home" Overview layout (experiment). Pure Dart, so it can be
// unit tested: which cards Overview shows, in what order, and each card's
// settings. Stored in private account data `im.nether.vommet.home_layout`:
//
//   {"cards": [{"id": "recent", "hidden": false, "count": 5, "dms": true,
//               "muted": true, "unreadOnly": false},
//              {"id": "favourites", "hidden": false},
//              {"id": "other_rooms", "hidden": false},
//              {"id": "mentions", "hidden": false},
//              {"id": "space-k3x9qa", "type": "space", "hidden": false,
//               "options": {"space": "!abc:example.org",
//                           "spaceClient": "@me:example.org",
//                           "unreadOnly": false, "voice": true}}]}
//
// Each entry is one card instance. `id` is unique; `type` says which card it
// is and defaults to `id`, so step 1's entries ("recent", "favourites",
// "other_rooms") read as before. Cards added from the Card library (step 3)
// whose id isn't their type keep their settings under "options": an older
// Vommet keeps unknown entries and their unknown fields as they are, but
// rewrites the top-level settings it knows only for its own cards.
//
// Reading is forgiving: unknown fields and unknown card types (a later
// version's cards) are kept as they are and written back untouched; missing
// or broken fields fall back to the defaults; step 1's three cards are added
// at the end when missing, and are hidden rather than deleted when removed,
// because an older Vommet would add them back.

import 'dart:math';

/// One card on Overview and its settings.
class HomeCard {
  const HomeCard(
    this.id, {
    String? type,
    this.hidden = false,
    this.count = HomeLayout.defaultCount,
    this.dms = true,
    this.muted = true,
    this.unreadOnly = false,
    this.space,
    this.spaceClient,
    this.voice = true,
    this.extra = const {},
  }) : _type = type;

  /// Unique within the layout.
  final String id;
  final String? _type;
  final bool hidden;

  /// Recent activity: how many rooms to show.
  final int count;

  /// Recent activity: include direct messages.
  final bool dms;

  /// Recent activity: include rooms you muted.
  final bool muted;

  /// Recent activity and Space: only rooms with unread messages.
  final bool unreadOnly;

  /// Space: the space's room id.
  final String? space;

  /// Space: the account the space was picked on (a client identifier).
  final String? spaceClient;

  /// Space: include voice rooms.
  final bool voice;

  /// Fields this version doesn't know, kept so they survive a save.
  final Map<String, dynamic> extra;

  /// Which card this is ([HomeLayout.knownTypes]); defaults to [id].
  String get type => _type ?? id;

  bool get known => HomeLayout.knownTypes.contains(type);

  /// A whole page (People, Rooms browser) rather than a card.
  bool get wholePage => HomeLayout.wholePageTypes.contains(type);

  /// One of step 1's cards: hidden, not deleted, when removed.
  bool get isDefault => HomeLayout.defaultIds.contains(id);

  /// Whether the card has settings of its own (⋯ Settings…).
  bool get configurable => HomeLayout.configurableTypes.contains(type);

  /// Settings are written under "options" unless the id is the type.
  bool get _nested => type != id;

  HomeCard copyWith({
    bool? hidden,
    int? count,
    bool? dms,
    bool? muted,
    bool? unreadOnly,
    String? space,
    String? spaceClient,
    bool? voice,
  }) =>
      HomeCard(id,
          type: _type,
          hidden: hidden ?? this.hidden,
          count: count ?? this.count,
          dms: dms ?? this.dms,
          muted: muted ?? this.muted,
          unreadOnly: unreadOnly ?? this.unreadOnly,
          space: space ?? this.space,
          spaceClient: spaceClient ?? this.spaceClient,
          voice: voice ?? this.voice,
          extra: extra);

  static HomeCard? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json["id"];
    if (id is! String || id.isEmpty) return null;
    final rawType = json["type"];
    final type = rawType is String && rawType.isNotEmpty ? rawType : null;
    final options = json["options"];
    // Settings: top level (step 1) with "options" on top.
    final settings = <Object?, Object?>{
      ...json,
      if (options is Map) ...options,
    };
    final count = settings["count"];
    final space = settings["space"];
    final spaceClient = settings["spaceClient"];
    return HomeCard(
      id,
      type: type == id ? null : type,
      hidden: _bool(json["hidden"], false),
      count: count is int && count > 0 && count <= HomeLayout.maxCount
          ? count
          : HomeLayout.defaultCount,
      dms: _bool(settings["dms"], true),
      muted: _bool(settings["muted"], true),
      unreadOnly: _bool(settings["unreadOnly"], false),
      space: space is String && space.isNotEmpty ? space : null,
      spaceClient:
          spaceClient is String && spaceClient.isNotEmpty ? spaceClient : null,
      voice: _bool(settings["voice"], true),
      extra: {
        for (final e in json.entries)
          if (e.key is String && !_fields.contains(e.key))
            e.key as String: e.value
      },
    );
  }

  Map<String, dynamic> get _settings => switch (type) {
        HomeLayout.recent => {
            "count": count,
            "dms": dms,
            "muted": muted,
            "unreadOnly": unreadOnly,
          },
        HomeLayout.spaceCard => {
            if (space != null) "space": space,
            if (spaceClient != null) "spaceClient": spaceClient,
            "unreadOnly": unreadOnly,
            "voice": voice,
          },
        _ => const <String, dynamic>{},
      };

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{...extra, "id": id};
    if (_nested) json["type"] = type;
    json["hidden"] = hidden;
    final settings = _settings;
    if (settings.isNotEmpty) {
      if (_nested) {
        json["options"] = settings;
      } else {
        json.addAll(settings);
      }
    }
    return json;
  }

  static const _fields = {
    "id",
    "type",
    "hidden",
    "options",
    "count",
    "dms",
    "muted",
    "unreadOnly",
    "space",
    "spaceClient",
    "voice",
  };

  static bool _bool(Object? v, bool fallback) => v is bool ? v : fallback;

  @override
  bool operator ==(Object other) =>
      other is HomeCard &&
      other.id == id &&
      other.type == type &&
      other.hidden == hidden &&
      other.count == count &&
      other.dms == dms &&
      other.muted == muted &&
      other.unreadOnly == unreadOnly &&
      other.space == space &&
      other.spaceClient == spaceClient &&
      other.voice == voice;

  @override
  int get hashCode => Object.hash(id, type, hidden, count, dms, muted,
      unreadOnly, space, spaceClient, voice);

  @override
  String toString() => "HomeCard($id, $type${hidden ? ", hidden" : ""})";
}

/// The Overview cards in order, known or not.
class HomeLayout {
  const HomeLayout(this.cards, {this.extra = const {}, this.inTab = false});

  /// A tab's main page (Home tabs) rather than the old Overview layout:
  /// step 1's cards aren't added back or kept hidden; removing deletes.
  final bool inTab;

  static const String accountDataKey = "im.nether.vommet.home_layout";

  static const String recent = "recent";
  static const String favourites = "favourites";
  static const String otherRooms = "other_rooms";
  static const String unread = "unread";
  static const String mentions = "mentions";
  static const String invites = "invites";
  static const String activeNow = "active_now";
  static const String lowPriority = "low_priority";
  static const String spaceCard = "space";
  static const String contacts = "contacts";

  /// Whole pages placed like cards: People (contacts, requests, invites)
  /// and the Rooms browser.
  static const String peoplePage = "people_page";
  static const String roomsPage = "rooms_page";

  /// The whole pages, each at most once on a main page.
  static const List<String> wholePageTypes = [peoplePage, roomsPage];

  /// Step 1's cards: the default Overview, in order.
  static const List<String> defaultIds = [recent, favourites, otherRooms];

  /// Every card this version can show, in Card library order.
  static const List<String> knownTypes = [
    recent,
    favourites,
    otherRooms,
    unread,
    mentions,
    invites,
    activeNow,
    lowPriority,
    spaceCard,
    contacts,
    peoplePage,
    roomsPage,
  ];

  /// Cards that can be on Overview more than once, each with its settings.
  static const Set<String> multiTypes = {recent, spaceCard};

  /// Cards with a Settings… dialog.
  static const Set<String> configurableTypes = {recent, spaceCard};

  /// The counts Recent activity offers.
  static const List<int> counts = [5, 10, 20];
  static const int defaultCount = 5;
  static const int maxCount = 100;

  /// Every card, including types this version doesn't know (kept, not
  /// shown) and hidden step-1 cards.
  final List<HomeCard> cards;

  /// Top-level fields this version doesn't know.
  final Map<String, dynamic> extra;

  static HomeLayout get defaults =>
      HomeLayout([for (final id in defaultIds) HomeCard(id)]);

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
    for (final id in defaultIds) {
      if (seen.add(id)) cards.add(HomeCard(id));
    }
    return HomeLayout(cards, extra: {
      for (final e in (content ?? const {}).entries)
        if (e.key != "cards") e.key: e.value
    });
  }

  /// A tab's main page from its "cards" list: as [parse], without adding
  /// step 1's cards.
  static HomeLayout parseCards(List list) {
    final cards = <HomeCard>[];
    final seen = <String>{};
    for (final item in list) {
      final card = HomeCard.fromJson(item);
      if (card == null || !seen.add(card.id)) continue;
      cards.add(card);
    }
    return HomeLayout(cards, inTab: true);
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

  /// Known cards the user hid (step 1's cards, removed).
  List<HomeCard> get hidden => [
        for (final c in cards)
          if (c.known && c.hidden) c
      ];

  /// Whether a card of [type] is on Overview.
  bool shows(String type) => visible.any((c) => c.type == type);

  /// The only thing shown is one whole page, which then fills the main
  /// page and scrolls by itself, as the People and Rooms pages always did.
  HomeCard? get soleWholePage {
    final v = visible;
    return v.length == 1 && v.single.wholePage ? v.single : null;
  }

  /// Whether the library can add another card of [type].
  bool canAdd(String type) =>
      knownTypes.contains(type) && (multiTypes.contains(type) || !shows(type));

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
    return HomeLayout(next, extra: extra, inTab: inTab);
  }

  /// Where a card dropped into visible gap [gap] goes in [cards]: gap 0 is
  /// above the first visible card, gap `visible.length` below the last.
  /// Hidden and unknown cards keep their places.
  int _indexForGap(int gap) {
    final v = visible;
    if (v.isEmpty) return cards.length;
    final g = gap.clamp(0, v.length);
    if (g < v.length) return cards.indexWhere((c) => c.id == v[g].id);
    return cards.indexWhere((c) => c.id == v.last.id) + 1;
  }

  /// Moves [id] into visible gap [gap], counted before it moves (a drop
  /// indicator's position, or a ReorderableListView's newIndex).
  HomeLayout moveTo(String id, int gap) {
    final v = visible;
    final from = v.indexWhere((c) => c.id == id);
    if (from < 0 || gap == from || gap == from + 1) return this;
    final card = v[from];
    final after = gap > from ? gap - 1 : gap;
    final rest = HomeLayout([
      for (final c in cards)
        if (c.id != id) c
    ], extra: extra, inTab: inTab);
    final index = rest._indexForGap(after);
    return HomeLayout([...rest.cards]..insert(index, card),
        extra: extra, inTab: inTab);
  }

  /// A unique id for a new card of [type]: the type itself for a one-off
  /// card when it's free, else the type with a random suffix.
  String newId(String type, {Random? random}) {
    final ids = {for (final c in cards) c.id};
    if (!multiTypes.contains(type) && !ids.contains(type)) return type;
    final r = random ?? Random();
    const letters = "abcdefghijklmnopqrstuvwxyz0123456789";
    while (true) {
      final suffix =
          List.generate(6, (_) => letters[r.nextInt(letters.length)]).join();
      final id = "$type-$suffix";
      if (!ids.contains(id)) return id;
    }
  }

  /// A new card of [type] with its default settings and a unique id.
  HomeCard newCard(String type, {Random? random}) {
    final id = newId(type, random: random);
    return HomeCard(id, type: id == type ? null : type);
  }

  /// Puts [card] into visible gap [gap] (the end when null). A card with
  /// the same id is replaced, so a hidden step-1 card comes back here.
  HomeLayout insert(HomeCard card, {int? gap}) {
    final rest = HomeLayout([
      for (final c in cards)
        if (c.id != card.id) c
    ], extra: extra, inTab: inTab);
    final index = rest._indexForGap(gap ?? rest.visible.length);
    return HomeLayout([...rest.cards]..insert(index, card),
        extra: extra, inTab: inTab);
  }

  /// The library's add: a hidden card of [type] comes back at [gap];
  /// otherwise a new card, if [canAdd] allows one.
  HomeLayout add(String type, {int? gap, Random? random}) {
    final back = cards.where((c) => c.type == type && c.hidden).firstOrNull;
    if (back != null) return insert(back.copyWith(hidden: false), gap: gap);
    if (!canAdd(type)) return this;
    return insert(newCard(type, random: random), gap: gap);
  }

  /// ✕ / drag back to the library: step 1's cards are hidden (an older
  /// Vommet would add them back), every other card is deleted.
  HomeLayout remove(String id) {
    final card = cards.where((c) => c.id == id).firstOrNull;
    if (card == null) return this;
    if (card.isDefault && !inTab) {
      return replace(card.copyWith(hidden: true));
    }
    return HomeLayout([
      for (final c in cards)
        if (c.id != id) c
    ], extra: extra, inTab: inTab);
  }

  HomeLayout replace(HomeCard card) =>
      HomeLayout([for (final c in cards) c.id == card.id ? card : c],
          extra: extra, inTab: inTab);

  HomeLayout hide(String id) => replace(card(id).copyWith(hidden: true));

  /// "Add back": shows every hidden card again, where it was.
  HomeLayout showAll() => HomeLayout(
      [for (final c in cards) c.known ? c.copyWith(hidden: false) : c],
      extra: extra, inTab: inTab);

  /// "Restore defaults": step 1's three cards with their default settings.
  HomeLayout restoreDefaults() =>
      HomeLayout(defaults.cards, extra: extra, inTab: inTab);
}

/// A short line saying what a card shows with its settings, for the phone
/// customize list and the customize-mode card headers. Null for cards
/// without settings (the UI uses the library's description).
String? cardSummary(HomeCard card) {
  switch (card.type) {
    case HomeLayout.recent:
      final parts = <String>[
        card.unreadOnly
            ? "Unread only · top ${card.count}"
            : "Top ${card.count}"
      ];
      if (!card.dms && !card.muted) {
        parts.add("no DMs or muted rooms");
      } else if (!card.dms) {
        parts.add("no DMs");
      } else if (!card.muted) {
        parts.add("no muted rooms");
      } else if (!card.unreadOnly) {
        parts.add("DMs and muted included");
      }
      return parts.join(" · ");
    case HomeLayout.spaceCard:
      return [
        "Space",
        card.unreadOnly ? "unread only" : "all rooms",
        if (!card.voice) "no voice rooms",
      ].join(" · ");
  }
  return null;
}

/// [items] newest first (a stable sort); items without any event go last.
List<T> newestFirst<T>(
    Iterable<T> items, DateTime? Function(T item) lastEvent) {
  final list = items.toList();
  final indexed = [for (var i = 0; i < list.length; i++) (i, list[i])];
  indexed.sort((a, b) {
    final ta = lastEvent(a.$2);
    final tb = lastEvent(b.$2);
    if (ta != null && tb != null) {
      final byTime = tb.compareTo(ta);
      if (byTime != 0) return byTime;
    } else if (ta != null) {
      return -1;
    } else if (tb != null) {
      return 1;
    }
    return a.$1.compareTo(b.$1);
  });
  return [for (final e in indexed) e.$2];
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
  return newestFirst(result, lastEvent).take(card.count).toList();
}

/// The Unread, Mentions & highlights and Low priority cards: the [items]
/// that [include], newest first.
List<T> roomsWhere<T>(
  Iterable<T> items, {
  required bool Function(T item) include,
  required DateTime? Function(T item) lastEvent,
}) =>
    newestFirst(items.where(include), lastEvent);

/// The Space card: the space's rooms (subspaces included, each room once)
/// that pass [card]'s filters, newest first.
List<T> spaceCardRooms<T>(
  Iterable<T> rooms,
  HomeCard card, {
  required DateTime? Function(T item) lastEvent,
  required bool Function(T item) isUnread,
  required bool Function(T item) isVoice,
}) {
  final seen = <T>{};
  return newestFirst([
    for (final room in rooms)
      if ((!card.unreadOnly || isUnread(room)) &&
          (card.voice || !isVoice(room)) &&
          seen.add(room))
        room
  ], lastEvent);
}
