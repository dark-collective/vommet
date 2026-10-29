// Vommet (New Home): the Rooms section. Pure Dart, so it can be unit
// tested. A side list section of type "standalone" (and the main page's
// Standalone rooms card, "other_rooms") picks its rooms with a
// [RoomsFilter]: standalone rooms, rooms in spaces (all of them, only the
// ones you pick, or all but those), the spaces themselves as rows, direct
// messages, only rooms with some of your tags, in an order you choose.
// Without any of these fields it is today's Standalone rooms, so a layout
// from before reads the same, and an older Vommet still shows the
// section's standalone rooms (and keeps the fields it doesn't know).
//
//   {"id": "standalone-k3x9qa", "type": "standalone", "name": "Gaming",
//    "standalone": false, "spaces": "only",
//    "spaceList": [{"space": "!abc:example.org",
//                   "spaceClient": "@me:example.org"}],
//    "spaceRows": true, "dms": false, "tags": ["u.Work", "u.Art"],
//    "order": "spaces_first", "spaceNames": false}
//
// On a card the same fields sit in one "rooms" object at the card's top
// level ("tags" and "name" included), as an older Vommet rewrites the
// settings it knows of its own cards.

/// A space picked in a Rooms section: its room id and the account it was
/// picked on.
class SpaceRef {
  const SpaceRef(this.space, [this.client]);

  final String space;
  final String? client;

  static SpaceRef? fromJson(Object? json) {
    if (json is! Map) return null;
    final space = json["space"];
    final client = json["spaceClient"];
    if (space is! String || space.isEmpty) return null;
    return SpaceRef(
        space, client is String && client.isNotEmpty ? client : null);
  }

  Map<String, dynamic> toJson() =>
      {"space": space, if (client != null) "spaceClient": client};

  @override
  bool operator ==(Object other) =>
      other is SpaceRef && other.space == space && other.client == client;

  @override
  int get hashCode => Object.hash(space, client);

  @override
  String toString() => "SpaceRef($space)";
}

/// Which rooms a Rooms section holds, and in what order.
class RoomsFilter {
  const RoomsFilter({
    this.standalone = true,
    this.spaces,
    this.spaceList = const [],
    this.spaceRows = false,
    this.dms = false,
    this.tags = const [],
    this.order = orderStandaloneFirst,
    this.spaceNames = true,
  });

  /// Rooms that aren't part of a space (and aren't direct messages).
  final bool standalone;

  /// Rooms in spaces: null for none, else [spacesAll], [spacesOnly] or
  /// [spacesExcept] (with [spaceList]).
  final String? spaces;
  final List<SpaceRef> spaceList;

  /// A row per space (tap to open it).
  final bool spaceRows;

  /// Direct messages too.
  final bool dms;

  /// Only rooms with any one of these tags (none: no tag filter).
  final List<String> tags;

  /// [orderStandaloneFirst], [orderSpacesFirst] or [orderNewest].
  final String order;

  /// The room's space, muted, after its name.
  final bool spaceNames;

  static const String spacesAll = "all";
  static const String spacesOnly = "only";
  static const String spacesExcept = "except";
  static const List<String> spaceModes = [spacesAll, spacesOnly, spacesExcept];

  static const String orderStandaloneFirst = "standalone_first";
  static const String orderSpacesFirst = "spaces_first";
  static const String orderNewest = "newest";
  static const List<String> orders = [
    orderStandaloneFirst,
    orderSpacesFirst,
    orderNewest
  ];

  /// Today's Standalone rooms.
  static const RoomsFilter standaloneOnly = RoomsFilter();

  /// The default Overview's Rooms: standalone rooms, then every space's.
  static const RoomsFilter everything = RoomsFilter(spaces: spacesAll);

  /// Whether it holds rooms in spaces (then it's called "Rooms").
  bool get inSpaces => spaces != null;

  /// The fields a section or card stores.
  static const Set<String> fields = {
    "standalone",
    "spaces",
    "spaceList",
    "spaceRows",
    "dms",
    "order",
    "spaceNames",
  };

  RoomsFilter copyWith({
    bool? standalone,
    String? spaces,
    bool clearSpaces = false,
    List<SpaceRef>? spaceList,
    bool? spaceRows,
    bool? dms,
    List<String>? tags,
    String? order,
    bool? spaceNames,
  }) =>
      RoomsFilter(
        standalone: standalone ?? this.standalone,
        spaces: clearSpaces ? null : spaces ?? this.spaces,
        spaceList: spaceList ?? this.spaceList,
        spaceRows: spaceRows ?? this.spaceRows,
        dms: dms ?? this.dms,
        tags: tags ?? this.tags,
        order: order ?? this.order,
        spaceNames: spaceNames ?? this.spaceNames,
      );

  /// Reads [fields] from [json]; [tags] come from the caller (a section
  /// keeps them in its own "tags").
  static RoomsFilter fromJson(Map json, {List<String> tags = const []}) {
    final spaces = json["spaces"];
    final list = json["spaceList"];
    final order = json["order"];
    return RoomsFilter(
      standalone: json["standalone"] is bool ? json["standalone"] : true,
      spaces: spaceModes.contains(spaces) ? spaces as String : null,
      spaceList: list is List
          ? [
              for (final item in list)
                if (SpaceRef.fromJson(item) case final ref?) ref
            ]
          : const [],
      spaceRows: json["spaceRows"] == true,
      dms: json["dms"] == true,
      tags: tags,
      order: orders.contains(order) ? order as String : orderStandaloneFirst,
      spaceNames: json["spaceNames"] is bool ? json["spaceNames"] : true,
    );
  }

  /// [fields] that differ from the defaults ([tags] not included).
  Map<String, dynamic> toJson() => {
        if (!standalone) "standalone": false,
        if (spaces != null) "spaces": spaces,
        if (spaceList.isNotEmpty)
          "spaceList": [for (final s in spaceList) s.toJson()],
        if (spaceRows) "spaceRows": true,
        if (dms) "dms": true,
        if (order != orderStandaloneFirst) "order": order,
        if (!spaceNames) "spaceNames": false,
      };

  /// A card's "rooms" object: [toJson] with the tags and [name].
  Map<String, dynamic> toCardJson({String? name}) => {
        ...toJson(),
        if (tags.isNotEmpty) "tags": tags,
        if (name != null) "name": name,
      };

  /// A card's "rooms" object, or [standaloneOnly].
  static RoomsFilter fromCardJson(Object? json) {
    if (json is! Map) return standaloneOnly;
    final tags = json["tags"];
    return fromJson(json, tags: [
      if (tags is List)
        for (final t in tags)
          if (t is String && t.isNotEmpty) t
    ]);
  }

  @override
  bool operator ==(Object other) =>
      other is RoomsFilter &&
      other.standalone == standalone &&
      other.spaces == spaces &&
      _same(other.spaceList, spaceList) &&
      other.spaceRows == spaceRows &&
      other.dms == dms &&
      _same(other.tags, tags) &&
      other.order == order &&
      other.spaceNames == spaceNames;

  @override
  int get hashCode => Object.hash(standalone, spaces, Object.hashAll(spaceList),
      spaceRows, dms, Object.hashAll(tags), order, spaceNames);

  @override
  String toString() => "RoomsFilter(${toCardJson()})";
}

bool _same<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// A Rooms section's name: its own, else "Rooms" when it holds rooms in
/// spaces, "Standalone rooms" when it doesn't. [onlySpace] names the one
/// space a section of just that space's rooms shows.
String roomsSectionLabel(RoomsFilter filter,
    {String? name, String? Function(SpaceRef ref)? onlySpace}) {
  if (name != null && name.trim().isNotEmpty) return name.trim();
  if (!filter.standalone &&
      !filter.dms &&
      filter.spaces == RoomsFilter.spacesOnly &&
      filter.spaceList.length == 1) {
    final space = onlySpace?.call(filter.spaceList.single);
    if (space != null) return space;
  }
  return filter.inSpaces ? "Rooms" : "Standalone rooms";
}

/// Where a room sits among your spaces: its spaces, outermost first, down
/// to the one holding it ([nearest]); [rail] is the outermost one's place
/// in the space rail.
class SpacePath<S> {
  const SpacePath(this.spaces, this.rail);
  final List<S> spaces;
  final int rail;
  S get nearest => spaces.last;
  S get outermost => spaces.first;
}

/// The deepest a space path goes (a guard against very deep or broken
/// space graphs).
const int maxSpaceDepth = 8;

/// One path per room: the first space holding it, walking [tops] in rail
/// order, each space's rooms before its subspaces, depth first. A space
/// already on the way down (a loop) isn't followed again, and nothing
/// deeper than [maxSpaceDepth] is. [key] identifies a room.
Map<Object, SpacePath<S>> spacePaths<S, R>(
  List<S> tops, {
  required Iterable<R> Function(S space) rooms,
  required Iterable<S> Function(S space) subspaces,
  required Object Function(R room) key,
  required Object Function(S space) spaceKey,
}) {
  final paths = <Object, SpacePath<S>>{};
  for (var rail = 0; rail < tops.length; rail++) {
    void walk(S space, List<S> path, Set<Object> on) {
      final here = [...path, space];
      for (final room in rooms(space)) {
        paths.putIfAbsent(key(room), () => SpacePath(here, rail));
      }
      if (here.length >= maxSpaceDepth) return;
      for (final sub in subspaces(space)) {
        final k = spaceKey(sub);
        if (on.contains(k)) continue;
        walk(sub, here, {...on, k});
      }
    }

    walk(tops[rail], const [], {spaceKey(tops[rail])});
  }
  return paths;
}

/// How a Rooms section reads a room. Lets tests use plain objects.
class RoomsFacts<R> {
  const RoomsFacts({
    required this.lastEvent,
    required this.isStandalone,
    required this.isDirectMessage,
    required this.hasTag,
    required this.railIndex,
    required this.inSpace,
    this.identity = _self,
  });

  final DateTime? Function(R room) lastEvent;

  /// Not in any space, and not a direct message (as the rail's Home counts).
  final bool Function(R room) isStandalone;
  final bool Function(R room) isDirectMessage;
  final bool Function(R room, String tag) hasTag;

  /// The room's outermost space's place in the rail, or null outside any
  /// space.
  final int? Function(R room) railIndex;

  /// Whether the room is in picked space [ref] (its subspaces too).
  final bool Function(R room, SpaceRef ref) inSpace;

  /// The same room joined from two accounts shares this.
  final Object Function(R room) identity;
}

Object _self(Object? room) => room as Object;

/// Whether [filter] takes [room].
bool roomsFilterTakes<R>(RoomsFilter filter, R room, RoomsFacts<R> facts) {
  if (filter.tags.isNotEmpty &&
      !filter.tags.any((t) => facts.hasTag(room, t))) {
    return false;
  }
  if (facts.isDirectMessage(room)) return filter.dms;
  if (facts.isStandalone(room)) return filter.standalone;
  final spaces = filter.spaces;
  if (spaces == null || facts.railIndex(room) == null) return false;
  return switch (spaces) {
    RoomsFilter.spacesOnly =>
      filter.spaceList.any((s) => facts.inSpace(room, s)),
    RoomsFilter.spacesExcept =>
      !filter.spaceList.any((s) => facts.inSpace(room, s)),
    _ => true,
  };
}

/// [rooms] (newest first already) in [filter]'s order: standalone rooms
/// and DMs as one block, spaces in rail order with each space's rooms
/// newest first; or simply newest first. Stable, so the same rooms always
/// come in the same order.
List<R> orderRoomsSection<R>(
    RoomsFilter filter, List<R> rooms, RoomsFacts<R> facts) {
  if (filter.order == RoomsFilter.orderNewest) return rooms;
  final outside = <R>[];
  final bySpace = <int, List<R>>{};
  for (final room in rooms) {
    final rail = facts.railIndex(room);
    if (rail == null || facts.isDirectMessage(room)) {
      outside.add(room);
    } else {
      (bySpace[rail] ??= []).add(room);
    }
  }
  final spaced = [
    for (final rail in bySpace.keys.toList()..sort()) ...bySpace[rail]!
  ];
  return filter.order == RoomsFilter.orderSpacesFirst
      ? [...spaced, ...outside]
      : [...outside, ...spaced];
}

/// A row of a Rooms section: a room, or (with "The spaces themselves") a
/// space.
class RoomsRow<R, S> {
  const RoomsRow.room(R this.room) : space = null;
  const RoomsRow.space(S this.space) : room = null;
  final R? room;
  final S? space;
}

/// [rooms] (already ordered) with a row per space of [spaces] (the
/// section's spaces in rail order, with their rail index) when [filter]
/// asks for them: each space right before its rooms, or all of them first
/// when the order is newest first.
List<RoomsRow<R, S>> roomsSectionRows<R, S>(RoomsFilter filter, List<R> rooms,
    List<(int, S)> spaces, int? Function(R room) railIndex,
    {bool Function(R room)? isDirectMessage}) {
  if (!filter.spaceRows || spaces.isEmpty) {
    return [for (final r in rooms) RoomsRow.room(r)];
  }
  if (filter.order == RoomsFilter.orderNewest) {
    return [
      for (final (_, s) in spaces) RoomsRow.space(s),
      for (final r in rooms) RoomsRow.room(r),
    ];
  }
  final result = <RoomsRow<R, S>>[];
  var next = 0;
  void spacesUpTo(int rail) {
    while (next < spaces.length && spaces[next].$1 <= rail) {
      result.add(RoomsRow.space(spaces[next].$2));
      next++;
    }
  }

  final spacesFirst = filter.order == RoomsFilter.orderSpacesFirst;
  for (final room in rooms) {
    final rail = isDirectMessage?.call(room) == true ? null : railIndex(room);
    // Standalone first: the spaces come after the standalone block.
    if (rail != null) {
      spacesUpTo(rail);
    } else if (spacesFirst) {
      spacesUpTo(1 << 30);
    }
    result.add(RoomsRow.room(room));
  }
  spacesUpTo(1 << 30);
  return result;
}
