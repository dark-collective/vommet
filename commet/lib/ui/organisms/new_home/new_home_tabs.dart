// Vommet (New Home): customizable Home tabs (Vommet issues 604 and 607).
// Pure Dart, so it can be unit tested. Home is an ordered list of tabs; each
// tab has a side list (sections of rooms, in Home's column) and a main page
// (cards and whole pages, new_home_layout.dart). Overview, People and Rooms
// are only the default tabs. Stored in the same private account data as the
// old Overview layout, `im.nether.vommet.home_layout`:
//
//   {"version": 2,
//    "tabs": [{"id": "overview", "name": "Overview", "icon": "dashboard",
//              "side": [{"id": "favourites"}, {"id": "recent"}],
//              "cards": [{"id": "mentions"}, {"id": "invites"},
//                        {"id": "active_now"}]},
//             {"id": "tab-k3x9qa", "name": "Gaming", "icon": "gamepad",
//              "side": [{"id": "space-a1b2c3", "type": "space",
//                        "space": "!abc:example.org",
//                        "spaceClient": "@me:example.org"},
//                       {"id": "low_priority", "collapsed": true}],
//              "cards": [{"id": "rooms_page"}]}],
//             (a tag section: {"id": "tag-p0q1r2", "type": "tag",
//              "tag": "u.Gaming"}; All my tags: {"id": "all_tags",
//              "collapsedTags": ["u.Work"]})
//    "cards": [... the old Overview layout, left as it was ...]}
//
// The old top-level "cards" stays untouched, so an older Vommet keeps
// showing its Overview. A layout without "tabs" is migrated: an Overview
// someone customized keeps its cards on the Overview tab's main page;
// otherwise the new defaults apply. Unknown fields, tabs' unknown fields and
// unknown section types are kept and written back as they were.

import 'dart:math';

import 'package:commet/ui/organisms/new_home/new_home_layout.dart';

/// One section of a tab's side list: a collapsible list of rooms.
class HomeSection {
  const HomeSection(
    this.id, {
    String? type,
    this.collapsed = false,
    this.space,
    this.spaceClient,
    this.tag,
    this.collapsedTags = const [],
    this.parent,
    this.extra = const {},
  }) : _type = type;

  static const String favourites = "favourites";
  static const String recent = "recent";
  static const String directMessages = "dms";
  static const String voice = "voice";
  static const String liveVoice = "live_voice";
  static const String photos = "photos";
  static const String standalone = "standalone";
  static const String spaceSection = "space";
  static const String lowPriority = "low_priority";

  /// Rooms with one of your own room tags (`u.*`, the ones other Matrix
  /// apps such as Nheko show too).
  static const String tagSection = "tag";

  /// A section per room tag you use, each like [tagSection].
  static const String allTags = "all_tags";

  /// Every section this version can show, in library order.
  static const List<String> knownTypes = [
    favourites,
    recent,
    directMessages,
    voice,
    liveVoice,
    photos,
    standalone,
    spaceSection,
    lowPriority,
    tagSection,
    allTags,
  ];

  /// Sections a side list can hold more than once (one per space or tag).
  static const Set<String> multiTypes = {spaceSection, tagSection};

  /// Unique within its side list.
  final String id;
  final String? _type;

  /// Shown as its header only.
  final bool collapsed;

  /// A space's rooms: the space's room id.
  final String? space;

  /// A space's rooms: the account the space was picked on.
  final String? spaceClient;

  /// A tag section: the room tag, e.g. `u.Gaming`.
  final String? tag;

  /// All my tags: the tags whose sections are collapsed.
  final List<String> collapsedTags;

  /// A section All my tags made for one tag (never saved): the id of that
  /// All my tags section.
  final String? parent;

  /// Fields this version doesn't know, kept so they survive a save.
  final Map<String, dynamic> extra;

  String get type => _type ?? id;
  bool get known => knownTypes.contains(type);

  HomeSection copyWith(
          {bool? collapsed,
          String? space,
          String? spaceClient,
          String? tag,
          List<String>? collapsedTags}) =>
      HomeSection(id,
          type: _type,
          collapsed: collapsed ?? this.collapsed,
          space: space ?? this.space,
          spaceClient: spaceClient ?? this.spaceClient,
          tag: tag ?? this.tag,
          collapsedTags: collapsedTags ?? this.collapsedTags,
          parent: parent,
          extra: extra);

  static HomeSection? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json["id"];
    if (id is! String || id.isEmpty) return null;
    final type = json["type"];
    final space = json["space"];
    final spaceClient = json["spaceClient"];
    final tag = json["tag"];
    final collapsedTags = json["collapsedTags"];
    return HomeSection(id,
        type: type is String && type.isNotEmpty && type != id ? type : null,
        collapsed: json["collapsed"] == true,
        space: space is String && space.isNotEmpty ? space : null,
        spaceClient: spaceClient is String && spaceClient.isNotEmpty
            ? spaceClient
            : null,
        tag: tag is String && tag.isNotEmpty ? tag : null,
        collapsedTags: collapsedTags is List
            ? [
                for (final t in collapsedTags)
                  if (t is String && t.isNotEmpty) t
              ]
            : const [],
        extra: {
          for (final e in json.entries)
            if (e.key is String && !_fields.contains(e.key))
              e.key as String: e.value
        });
  }

  Map<String, dynamic> toJson() => {
        ...extra,
        "id": id,
        if (type != id) "type": type,
        if (collapsed) "collapsed": true,
        if (space != null) "space": space,
        if (spaceClient != null) "spaceClient": spaceClient,
        if (tag != null) "tag": tag,
        if (collapsedTags.isNotEmpty) "collapsedTags": collapsedTags,
      };

  static const _fields = {
    "id",
    "type",
    "collapsed",
    "space",
    "spaceClient",
    "tag",
    "collapsedTags",
  };

  @override
  bool operator ==(Object other) =>
      other is HomeSection &&
      other.id == id &&
      other.type == type &&
      other.collapsed == collapsed &&
      other.space == space &&
      other.spaceClient == spaceClient &&
      other.tag == tag &&
      other.parent == parent &&
      _sameList(other.collapsedTags, collapsedTags);

  @override
  int get hashCode => Object.hash(id, type, collapsed, space, spaceClient, tag,
      parent, Object.hashAll(collapsedTags));

  @override
  String toString() =>
      "HomeSection($id, $type${collapsed ? ", collapsed" : ""})";
}

/// One Home tab: its name and icon, its side list and its main page.
class HomeTab {
  const HomeTab(
    this.id, {
    required this.name,
    this.icon = HomeTabs.defaultIcon,
    this.side = const [],
    this.main = const HomeLayout([], inTab: true),
    this.rail,
    this.extra = const {},
  });

  /// Unique within Home.
  final String id;
  final String name;

  /// An icon name from [HomeTabs.icons]; unknown names draw the default.
  final String icon;

  /// The side list's sections, in order, known or not.
  final List<HomeSection> side;

  /// The main page's cards and whole pages.
  final HomeLayout main;

  /// Whether the sidebar shows a button for this tab under Home. Null when
  /// it was never chosen: the app then decides (People and Rooms follow
  /// their older sidebar settings, which first-run setup asks about).
  final bool? rail;

  /// Fields this version doesn't know.
  final Map<String, dynamic> extra;

  /// One of the three default tabs (Overview, People, Rooms).
  bool get isDefault => HomeTabs.defaultTabIds.contains(id);

  /// The sections this version shows, in order.
  List<HomeSection> get sections => [
        for (final s in side)
          if (s.known) s
      ];

  /// Whether the main page holds a card or whole page of [type].
  bool holds(String type) => main.shows(type);

  HomeTab copyWith(
          {String? name,
          String? icon,
          List<HomeSection>? side,
          HomeLayout? main,
          bool? rail}) =>
      HomeTab(id,
          name: name ?? this.name,
          icon: icon ?? this.icon,
          side: side ?? this.side,
          main: main ?? this.main,
          rail: rail ?? this.rail,
          extra: extra);

  /// Whether the library can add another section of [type].
  bool canAddSection(String type) =>
      HomeSection.knownTypes.contains(type) &&
      (HomeSection.multiTypes.contains(type) ||
          !side.any((s) => s.type == type));

  /// A unique id for a new section of [type].
  String newSectionId(String type, {Random? random}) =>
      _uniqueId(type, {for (final s in side) s.id},
          reuseType: !HomeSection.multiTypes.contains(type), random: random);

  /// Adds [section] at [index] (the end when null). A section with the same
  /// id is replaced.
  HomeTab addSection(HomeSection section, {int? index}) {
    final rest = [
      for (final s in side)
        if (s.id != section.id) s
    ];
    final at = (index ?? rest.length).clamp(0, rest.length);
    return copyWith(side: [...rest]..insert(at, section));
  }

  HomeTab removeSection(String id) => copyWith(side: [
        for (final s in side)
          if (s.id != id) s
      ]);

  HomeTab replaceSection(HomeSection section) =>
      copyWith(side: [for (final s in side) s.id == section.id ? section : s]);

  /// Moves section [id] into gap [gap] of the shown sections, counted
  /// before it moves (a ReorderableListView's newIndex).
  HomeTab moveSection(String id, int gap) {
    final shown = sections;
    final from = shown.indexWhere((s) => s.id == id);
    if (from < 0 || gap == from || gap == from + 1) return this;
    final moving = shown[from];
    final to = (gap > from ? gap - 1 : gap).clamp(0, shown.length - 1);
    final rest = [
      for (final s in side)
        if (s.id != id) s
    ];
    final others = [
      for (final s in shown)
        if (s.id != id) s
    ];
    final index = to < others.length
        ? rest.indexOf(others[to])
        : rest.indexOf(others.last) + 1;
    return copyWith(side: [...rest]..insert(index, moving));
  }

  static HomeTab? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json["id"];
    if (id is! String || id.isEmpty) return null;
    final name = json["name"];
    final icon = json["icon"];
    final side = <HomeSection>[];
    final seen = <String>{};
    final rawSide = json["side"];
    if (rawSide is List) {
      for (final item in rawSide) {
        final section = HomeSection.fromJson(item);
        if (section != null && seen.add(section.id)) side.add(section);
      }
    }
    final rawCards = json["cards"];
    final rail = json["rail"];
    return HomeTab(id,
        name: name is String && name.trim().isNotEmpty
            ? name.trim()
            : HomeTabs.defaultTab(id)?.name ?? "Tab",
        icon: icon is String && icon.isNotEmpty
            ? icon
            : HomeTabs.defaultTab(id)?.icon ?? HomeTabs.defaultIcon,
        side: side,
        main: HomeLayout.parseCards(rawCards is List ? rawCards : const []),
        rail: rail is bool ? rail : null,
        extra: {
          for (final e in json.entries)
            if (e.key is String && !_fields.contains(e.key))
              e.key as String: e.value
        });
  }

  Map<String, dynamic> toJson() => {
        ...extra,
        "id": id,
        "name": name,
        "icon": icon,
        "side": [for (final s in side) s.toJson()],
        "cards": [for (final c in main.cards) c.toJson()],
        if (rail != null) "rail": rail,
      };

  static const _fields = {"id", "name", "icon", "side", "cards", "rail"};

  @override
  String toString() => "HomeTab($id, $name)";
}

/// Home's tabs, in order. At least one.
class HomeTabs {
  const HomeTabs(this.tabs, {this.extra = const {}});

  static const int version = 2;

  static const String overview = "overview";
  static const String people = "people";
  static const String rooms = "rooms";

  /// The default tabs, in order.
  static const List<String> defaultTabIds = [overview, people, rooms];

  static const String defaultIcon = "dashboard";

  /// The icons a tab can have, in picker order.
  static const List<String> icons = [
    "dashboard",
    "people",
    "tag",
    "star",
    "chat",
    "mic",
    "gamepad",
    "music",
    "photo",
    "work",
    "school",
    "home",
    "heart",
    "code",
    "sports",
    "book",
  ];

  /// The longest name a tab can have.
  static const int maxName = 40;

  /// Every tab, in order.
  final List<HomeTab> tabs;

  /// Top-level fields this version doesn't know, and the old Overview
  /// layout ("cards"), kept as they were.
  final Map<String, dynamic> extra;

  /// The Overview tab's default main page: what needs you.
  static const List<String> overviewCards = [
    HomeLayout.mentions,
    HomeLayout.invites,
    HomeLayout.activeNow,
  ];

  /// One of the default tabs as Reset brings it back, or null.
  static HomeTab? defaultTab(String id) => switch (id) {
        overview => HomeTab(overview,
            name: "Overview",
            icon: "dashboard",
            side: const [
              HomeSection(HomeSection.favourites),
              HomeSection(HomeSection.recent),
            ],
            main: HomeLayout([for (final type in overviewCards) HomeCard(type)],
                inTab: true)),
        people => const HomeTab(people,
            name: "People",
            icon: "people",
            side: [HomeSection(HomeSection.directMessages)],
            main: HomeLayout([HomeCard(HomeLayout.peoplePage)], inTab: true)),
        rooms => const HomeTab(rooms,
            name: "Rooms",
            icon: "tag",
            side: [
              HomeSection(HomeSection.liveVoice),
              HomeSection(HomeSection.standalone),
              HomeSection(HomeSection.lowPriority, collapsed: true),
            ],
            main: HomeLayout([HomeCard(HomeLayout.roomsPage)], inTab: true)),
        _ => null,
      };

  static HomeTabs get defaults =>
      HomeTabs([for (final id in defaultTabIds) defaultTab(id)!]);

  static HomeTabs parse(Map<String, dynamic>? content) {
    final list = content?["tabs"];
    final tabs = <HomeTab>[];
    final seen = <String>{};
    if (list is List) {
      for (final item in list) {
        final tab = HomeTab.fromJson(item);
        if (tab != null && seen.add(tab.id)) tabs.add(tab);
      }
    }
    final extra = <String, dynamic>{
      for (final e in (content ?? const {}).entries)
        if (e.key != "tabs" && e.key != "version") e.key: e.value
    };
    if (tabs.isNotEmpty) return HomeTabs(tabs, extra: extra);
    return migrate(content, extra: extra);
  }

  /// A layout from before Home tabs: the default tabs, with the Overview
  /// someone customized kept as the Overview tab's main page.
  static HomeTabs migrate(Map<String, dynamic>? content,
      {Map<String, dynamic> extra = const {}}) {
    final defaults = HomeTabs.defaults;
    final cards = content?["cards"];
    if (cards is! List || cards.isEmpty) {
      return HomeTabs(defaults.tabs, extra: extra);
    }
    final old = HomeLayout.parse(content);
    if (_untouched(old)) return HomeTabs(defaults.tabs, extra: extra);
    final kept = HomeLayout([
      for (final c in old.cards)
        if (!c.hidden) c
    ], inTab: true);
    return HomeTabs([
      for (final tab in defaults.tabs)
        tab.id == overview ? tab.copyWith(main: kept) : tab
    ], extra: extra);
  }

  /// Step 1's three cards, in order, with their default settings.
  static bool _untouched(HomeLayout old) {
    final step1 = HomeLayout.defaults.cards;
    if (old.cards.length != step1.length) return false;
    for (var i = 0; i < step1.length; i++) {
      if (old.cards[i] != step1[i] || old.cards[i].extra.isNotEmpty) {
        return false;
      }
    }
    return true;
  }

  Map<String, dynamic> toJson() => {
        ...extra,
        "version": version,
        "tabs": [for (final t in tabs) t.toJson()],
      };

  HomeTab? tab(String id) => tabs.where((t) => t.id == id).firstOrNull;

  /// The first tab whose main page holds [type] (a card or whole page).
  HomeTab? tabHolding(String type) =>
      tabs.where((t) => t.holds(type)).firstOrNull;

  /// Default tabs that were removed, in their default order.
  List<String> get removedDefaults => [
        for (final id in defaultTabIds)
          if (tab(id) == null) id
      ];

  HomeTabs _with(List<HomeTab> next) => HomeTabs(next, extra: extra);

  HomeTabs replaceTab(HomeTab tab) =>
      _with([for (final t in tabs) t.id == tab.id ? tab : t]);

  /// Adds [tab] at [index] (the end when null).
  HomeTabs addTab(HomeTab tab, {int? index}) {
    final rest = [
      for (final t in tabs)
        if (t.id != tab.id) t
    ];
    final at = (index ?? rest.length).clamp(0, rest.length);
    return _with([...rest]..insert(at, tab));
  }

  /// Removes tab [id], unless it's the last one.
  HomeTabs removeTab(String id) {
    if (tabs.length <= 1) return this;
    return _with([
      for (final t in tabs)
        if (t.id != id) t
    ]);
  }

  bool canRemove(String id) => tabs.length > 1 && tab(id) != null;

  /// Moves tab [id] into gap [gap], counted before it moves (a
  /// ReorderableListView's newIndex).
  HomeTabs moveTab(String id, int gap) {
    final from = tabs.indexWhere((t) => t.id == id);
    if (from < 0 || gap == from || gap == from + 1) return this;
    final moving = tabs[from];
    final rest = [
      for (final t in tabs)
        if (t.id != id) t
    ];
    final to = (gap > from ? gap - 1 : gap).clamp(0, rest.length);
    return _with([...rest]..insert(to, moving));
  }

  /// Swaps tab [id] with its neighbour on the left (-1) or right (+1).
  HomeTabs shiftTab(String id, int direction) {
    final from = tabs.indexWhere((t) => t.id == id);
    final to = from + direction;
    if (from < 0 || to < 0 || to >= tabs.length) return this;
    final next = List<HomeTab>.of(tabs);
    next[from] = tabs[to];
    next[to] = tabs[from];
    return _with(next);
  }

  /// A unique id for a new tab.
  String newTabId({Random? random}) =>
      _uniqueId("tab", {for (final t in tabs) t.id},
          reuseType: false, random: random);

  /// A new, empty tab.
  HomeTab newTab(String name, String icon, {Random? random}) =>
      HomeTab(newTabId(random: random), name: cleanName(name), icon: icon);

  /// "New tab": an empty tab, a copy of tab [copyOf] (its side list and
  /// main page), or the removed default tab [restore] (keeping its id, so
  /// links to People and Rooms find it again), named [name] with [icon].
  /// Added after tab [after] (the end when null), with a sidebar button
  /// when [rail]. Returns the new tabs and
  /// the new tab's id.
  (HomeTabs, String) createTab(
      {required String name,
      required String icon,
      String? copyOf,
      String? restore,
      String? after,
      bool? rail,
      Random? random}) {
    final source = copyOf == null ? null : tab(copyOf);
    final restored =
        restore == null || tab(restore) != null ? null : defaultTab(restore);
    final id = restored?.id ?? newTabId(random: random);
    final base = restored ?? source;
    final created = HomeTab(id,
        name: cleanName(name),
        icon: icon,
        side: base?.side ?? const [],
        main: base?.main ?? const HomeLayout([], inTab: true),
        rail: rail);
    final at = after == null ? null : tabs.indexWhere((t) => t.id == after);
    return (
      addTab(created, index: at == null || at < 0 ? null : at + 1),
      id,
    );
  }

  /// A copy of tab [id] under a new id, right after it.
  HomeTabs duplicateTab(String id, {String? name, Random? random}) {
    final source = tab(id);
    if (source == null) return this;
    final copy = HomeTab(newTabId(random: random),
        name: cleanName(name ?? "${source.name} copy"),
        icon: source.icon,
        side: source.side,
        main: source.main,
        extra: source.extra);
    return addTab(copy, index: tabs.indexOf(source) + 1);
  }

  /// "Reset Home to default": the three default tabs. Unknown top-level
  /// fields and the old Overview layout stay.
  HomeTabs reset() => HomeTabs(defaults.tabs, extra: extra);

  /// A tab name: trimmed, at most [maxName] characters, never empty.
  static String cleanName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return "New tab";
    return trimmed.length <= maxName
        ? trimmed
        : trimmed.substring(0, maxName).trim();
  }
}

String _uniqueId(String type, Set<String> ids,
    {required bool reuseType, Random? random}) {
  if (reuseType && !ids.contains(type)) return type;
  final r = random ?? Random();
  const letters = "abcdefghijklmnopqrstuvwxyz0123456789";
  while (true) {
    final suffix =
        List.generate(6, (_) => letters[r.nextInt(letters.length)]).join();
    final id = "$type-$suffix";
    if (!ids.contains(id)) return id;
  }
}

/// How the side list reads a room. Lets tests use plain objects.
class SideListFacts<R> {
  const SideListFacts({
    required this.lastEvent,
    required this.isFavourite,
    required this.isDirectMessage,
    required this.isVoice,
    required this.isLive,
    required this.isPhotos,
    required this.isStandalone,
    required this.isLowPriority,
    required this.spaceRooms,
    this.hasTag = _noTag,
  });

  final DateTime? Function(R room) lastEvent;
  final bool Function(R room) isFavourite;
  final bool Function(R room) isDirectMessage;
  final bool Function(R room) isVoice;

  /// A voice room with a call going on.
  final bool Function(R room) isLive;
  final bool Function(R room) isPhotos;

  /// Not in any space, and not a direct message.
  final bool Function(R room) isStandalone;
  final bool Function(R room) isLowPriority;

  /// A space section's rooms (subspaces included), or null when the space
  /// isn't there (left, or not loaded yet).
  final Iterable<R>? Function(HomeSection section) spaceRooms;

  /// Whether the room has room tag [tag] (e.g. `u.Gaming`).
  final bool Function(R room, String tag) hasTag;
}

bool _noTag(Object? room, String tag) => false;

bool _sameList(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// [sections] with each All my tags section replaced by one tag section per
/// tag in [tags] (in that order) that the side list doesn't already show in
/// a tag section of its own. Those sections carry the All my tags section's
/// id as their [HomeSection.parent], and are collapsed when it lists their
/// tag in [HomeSection.collapsedTags].
List<HomeSection> expandTagSections(
    List<HomeSection> sections, List<String> tags) {
  final own = {
    for (final s in sections)
      if (s.type == HomeSection.tagSection && s.tag != null) s.tag!
  };
  return [
    for (final s in sections)
      if (s.type != HomeSection.allTags)
        s
      else
        for (final tag in tags)
          if (!own.contains(tag))
            HomeSection("${s.id}/$tag",
                type: HomeSection.tagSection,
                tag: tag,
                collapsed: s.collapsedTags.contains(tag),
                parent: s.id)
  ];
}

/// Collapses or expands the section All my tags ([allTags]) made for
/// [tag].
HomeSection toggleCollapsedTag(HomeSection allTags, String tag) {
  final collapsed = allTags.collapsedTags.contains(tag);
  return allTags.copyWith(collapsedTags: [
    for (final t in allTags.collapsedTags)
      if (t != tag) t,
    if (!collapsed) tag,
  ]);
}

/// Each of [sections]' rooms out of [rooms], newest first. A room shows
/// once per side list: the first section that takes it wins. When the side
/// list has a Low priority section, rooms marked low priority go there
/// (or to an earlier Favourites) and nowhere else. Recent activity leaves
/// out rooms without any event, like the old Home. Unknown sections get
/// no rooms.
List<List<R>> sideListRooms<R>(
    List<HomeSection> sections, Iterable<R> rooms, SideListFacts<R> facts) {
  final all = newestFirst(rooms, facts.lastEvent);
  final inList = all.toSet();
  final seen = <R>{};
  final lowSection = sections.any((s) => s.type == HomeSection.lowPriority);
  final result = <List<R>>[];
  for (final section in sections) {
    bool Function(R room)? take = switch (section.type) {
      HomeSection.favourites => facts.isFavourite,
      HomeSection.recent => (r) => facts.lastEvent(r) != null,
      HomeSection.directMessages => facts.isDirectMessage,
      HomeSection.voice => facts.isVoice,
      HomeSection.liveVoice => facts.isLive,
      HomeSection.photos => facts.isPhotos,
      HomeSection.standalone => facts.isStandalone,
      HomeSection.lowPriority => facts.isLowPriority,
      HomeSection.tagSection =>
        section.tag == null ? null : (r) => facts.hasTag(r, section.tag!),
      _ => null,
    };
    Iterable<R> candidates = all;
    if (section.type == HomeSection.spaceSection) {
      final members = facts.spaceRooms(section)?.toSet() ?? const {};
      candidates = all.where(members.contains);
      take = (_) => true;
    }
    final keepsLow = section.type == HomeSection.lowPriority ||
        section.type == HomeSection.favourites;
    final list = <R>[];
    if (take != null) {
      for (final room in candidates) {
        if (!inList.contains(room) || seen.contains(room)) continue;
        if (lowSection && !keepsLow && facts.isLowPriority(room)) continue;
        if (!take(room)) continue;
        seen.add(room);
        list.add(room);
      }
    }
    result.add(list);
  }
  return result;
}
