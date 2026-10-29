// Vommet (New Home): the Rooms section's model: which rooms it takes, its
// order and space rows, one space path per room, and that layouts stay
// readable both ways between this and older versions.
import 'package:commet/ui/organisms/new_home/new_home_layout.dart';
import 'package:commet/ui/organisms/new_home/new_home_rooms_section.dart';
import 'package:commet/ui/organisms/new_home/new_home_tabs.dart';
import 'package:flutter_test/flutter_test.dart';

/// A stand-in room: [rail] is its outermost space's place in the rail
/// (null outside spaces), [spaces] the picked spaces it's in.
class _R {
  const _R(this.name, this.minute,
      {this.rail,
      this.dm = false,
      this.spaces = const [],
      this.tags = const [],
      this.id});
  final String name;
  final int minute;
  final int? rail;
  final bool dm;
  final List<String> spaces;
  final List<String> tags;

  /// The same room joined from another account shares it.
  final String? id;

  @override
  String toString() => name;
}

final _facts = RoomsFacts<_R>(
  lastEvent: (r) => DateTime.utc(2026, 10, 26).add(Duration(minutes: r.minute)),
  isStandalone: (r) => r.rail == null && !r.dm,
  isDirectMessage: (r) => r.dm,
  hasTag: (r, t) => r.tags.contains(t),
  railIndex: (r) => r.rail,
  inSpace: (r, ref) => r.spaces.contains(ref.space),
  identity: (r) => r.id ?? r.name,
);

const _lounge = _R("Lounge", 50);
const _retro = _R("Retro chat", 10);
const _alice = _R("Alice", 60, dm: true);
const _raid =
    _R("Raid night", 40, rail: 0, spaces: ["!guild"], tags: ["u.Games"]);
const _builds = _R("Builds", 30, rail: 1, spaces: ["!nether", "!infra"]);
const _general = _R("General", 20, rail: 1, spaces: ["!nether"]);
const _books = _R("Books", 5, rail: 2, spaces: ["!club"], tags: ["u.Games"]);

const _all = [_alice, _lounge, _raid, _builds, _general, _retro, _books];

List<String> _taken(RoomsFilter filter) => [
      for (final r in _all)
        if (roomsFilterTakes(filter, r, _facts)) r.name
    ];

List<String> _side(List<HomeSection> sections, List<_R> rooms) =>
    sideListRooms<_R>(
      sections,
      rooms,
      SideListFacts(
        lastEvent: _facts.lastEvent,
        isFavourite: (_) => false,
        isDirectMessage: (r) => r.dm,
        isVoice: (_) => false,
        isLive: (_) => false,
        isPhotos: (_) => false,
        isStandalone: (r) => r.rail == null && !r.dm,
        isLowPriority: (_) => false,
        spaceRooms: (_) => null,
        rooms: _facts,
      ),
    ).last.map((r) => r.name).toList();

void main() {
  group("Which rooms", () {
    test("standalone only (today's Standalone rooms)", () {
      expect(_taken(RoomsFilter.standaloneOnly), ["Lounge", "Retro chat"]);
    });

    test("standalone and every space's rooms (the new default)", () {
      expect(_taken(RoomsFilter.everything),
          ["Lounge", "Raid night", "Builds", "General", "Retro chat", "Books"]);
    });

    test("only some spaces, subspaces included; all but some", () {
      const only = RoomsFilter(
          standalone: false,
          spaces: RoomsFilter.spacesOnly,
          spaceList: [SpaceRef("!nether")]);
      expect(_taken(only), ["Builds", "General"]);
      const sub = RoomsFilter(
          standalone: false,
          spaces: RoomsFilter.spacesOnly,
          spaceList: [SpaceRef("!infra")]);
      expect(_taken(sub), ["Builds"]);
      const except = RoomsFilter(
          standalone: false,
          spaces: RoomsFilter.spacesExcept,
          spaceList: [SpaceRef("!nether")]);
      expect(_taken(except), ["Raid night", "Books"]);
    });

    test("direct messages only when asked for", () {
      expect(_taken(const RoomsFilter(dms: true)),
          ["Alice", "Lounge", "Retro chat"]);
    });

    test("a tag filter applies to every kind", () {
      expect(
          _taken(const RoomsFilter(
              spaces: RoomsFilter.spacesAll, tags: ["u.Games"])),
          ["Raid night", "Books"]);
    });
  });

  group("Order", () {
    // Newest first, as the side list hands them over.
    final newest = [_lounge, _raid, _builds, _general, _retro, _books];

    test("standalone first, then spaces in rail order, newest within", () {
      expect(
          orderRoomsSection(RoomsFilter.everything, newest, _facts)
              .map((r) => r.name),
          ["Lounge", "Retro chat", "Raid night", "Builds", "General", "Books"]);
    });

    test("spaces first", () {
      const filter = RoomsFilter(
          spaces: RoomsFilter.spacesAll, order: RoomsFilter.orderSpacesFirst);
      expect(orderRoomsSection(filter, newest, _facts).map((r) => r.name),
          ["Raid night", "Builds", "General", "Books", "Lounge", "Retro chat"]);
    });

    test("newest first keeps the side list's order", () {
      const filter = RoomsFilter(
          spaces: RoomsFilter.spacesAll, order: RoomsFilter.orderNewest);
      expect(orderRoomsSection(filter, newest, _facts), newest);
    });

    test("space rows go right before their rooms", () {
      const filter =
          RoomsFilter(spaces: RoomsFilter.spacesAll, spaceRows: true);
      final rows = roomsSectionRows<_R, String>(
          filter,
          orderRoomsSection(filter, newest, _facts),
          const [(0, "Guild"), (1, "Nether"), (2, "Club"), (3, "Empty")],
          (r) => r.rail);
      expect(rows.map((r) => r.room?.name ?? "[${r.space}]"), [
        "Lounge",
        "Retro chat",
        "[Guild]",
        "Raid night",
        "[Nether]",
        "Builds",
        "General",
        "[Club]",
        "Books",
        "[Empty]",
      ]);
    });

    test("newest first: the space rows come first", () {
      const filter = RoomsFilter(
          spaces: RoomsFilter.spacesAll,
          spaceRows: true,
          order: RoomsFilter.orderNewest);
      final rows = roomsSectionRows<_R, String>(
          filter, [_raid, _lounge], const [(0, "Guild")], (r) => r.rail);
      expect(rows.map((r) => r.room?.name ?? "[${r.space}]"),
          ["[Guild]", "Raid night", "Lounge"]);
    });
  });

  group("Side list", () {
    test("the default Overview: DMs above take the DMs, Rooms the rest", () {
      final side = HomeTabs.defaults.tab("overview")!.side;
      expect(_side(side, _all),
          ["Lounge", "Retro chat", "Raid night", "Builds", "General", "Books"]);
    });

    test("a room joined from two accounts shows once", () {
      const other = _R("Lounge", 55, id: "Lounge");
      expect(
          _side([const HomeSection(HomeSection.standalone)],
              [_lounge, other, _retro]),
          ["Lounge", "Retro chat"]);
    });
  });

  group("Space paths", () {
    // Spaces as names; each has rooms and subspaces.
    final rooms = <String, List<String>>{
      "Nether": ["general"],
      "Infra": ["builds", "general"],
      "Guild": ["raid", "builds"],
      "Loop": ["loop-room"],
    };
    final subs = <String, List<String>>{
      "Nether": ["Infra"],
      "Infra": ["Loop"],
      "Loop": ["Infra", "Nether"],
    };
    Map<Object, SpacePath<String>> paths(List<String> tops) =>
        spacePaths<String, String>(tops,
            rooms: (s) => rooms[s] ?? const [],
            subspaces: (s) => subs[s] ?? const [],
            key: (r) => r,
            spaceKey: (s) => s);

    test("one path per room: the first in rail order wins", () {
      final p = paths(["Nether", "Guild"]);
      expect(p["general"]!.spaces, ["Nether"]);
      expect(p["builds"]!.spaces, ["Nether", "Infra"]);
      expect(p["builds"]!.nearest, "Infra");
      expect(p["builds"]!.rail, 0);
      expect(p["raid"]!.rail, 1);
      // The rail order decides.
      expect(paths(["Guild", "Nether"])["builds"]!.spaces, ["Guild"]);
    });

    test("loops and very deep spaces end", () {
      final p = paths(["Nether"]);
      expect(p["loop-room"]!.spaces, ["Nether", "Infra", "Loop"]);
      // A chain deeper than the guard.
      final deep = spacePaths<int, String>([0],
          rooms: (s) => ["room-$s"],
          subspaces: (s) => [s + 1],
          key: (r) => r,
          spaceKey: (s) => s);
      expect(deep.length, maxSpaceDepth);
    });
  });

  group("Names", () {
    test("Rooms, Standalone rooms, a single space's, or its own", () {
      expect(roomsSectionLabel(RoomsFilter.standaloneOnly), "Standalone rooms");
      expect(roomsSectionLabel(RoomsFilter.everything), "Rooms");
      const one = RoomsFilter(
          standalone: false,
          spaces: RoomsFilter.spacesOnly,
          spaceList: [SpaceRef("!nether")]);
      expect(roomsSectionLabel(one, onlySpace: (_) => "Nether"), "Nether");
      expect(roomsSectionLabel(one, onlySpace: (_) => null), "Rooms");
      expect(roomsSectionLabel(one, name: " Mine "), "Mine");
    });
  });

  group("Saved layouts", () {
    test("an old Standalone rooms section reads and saves unchanged", () {
      final old = {"id": "standalone", "collapsed": true, "future": 1};
      final section = HomeSection.fromJson(old)!;
      expect(section.rooms, RoomsFilter.standaloneOnly);
      expect(section.toJson(), old);
      // Edited: everything it doesn't know is kept.
      final edited = section.copyWith(collapsed: false);
      expect(edited.toJson(), {"id": "standalone", "future": 1});
    });

    test("a Rooms section round-trips its settings and unknown fields", () {
      final json = {
        "id": "standalone-k3x9qa",
        "type": "standalone",
        "name": "Gaming",
        "standalone": false,
        "spaces": "only",
        "spaceList": [
          {"space": "!abc:example.org", "spaceClient": "@me:example.org"}
        ],
        "spaceRows": true,
        "dms": true,
        "tags": ["u.Work", "u.Art"],
        "order": "spaces_first",
        "spaceNames": false,
        "future": {"x": 1},
      };
      final section = HomeSection.fromJson(json)!;
      final rooms = section.rooms;
      expect(rooms.standalone, isFalse);
      expect(rooms.spaces, RoomsFilter.spacesOnly);
      expect(rooms.spaceList,
          [const SpaceRef("!abc:example.org", "@me:example.org")]);
      expect(rooms.tags, ["u.Work", "u.Art"]);
      expect(rooms.order, RoomsFilter.orderSpacesFirst);
      expect(rooms.spaceNames, isFalse);
      expect(section.extra, {
        "future": {"x": 1}
      });
      // Saved as read (plus "tag", the first tag, for older versions).
      expect(section.toJson(), {...json, "tag": "u.Work"});
      // Collapsing (an edit every version makes) keeps it all.
      expect(section.copyWith(collapsed: true).toJson(),
          {...json, "tag": "u.Work", "collapsed": true});
      // Changing its settings keeps the unknown field.
      final changed = section.copyWith(
          rooms: rooms.copyWith(order: RoomsFilter.orderNewest, tags: []));
      expect(changed.toJson()["order"], "newest");
      expect(changed.toJson()["future"], {"x": 1});
      expect(changed.tags, isEmpty);
    });

    test("an older Vommet keeps the new fields (they're unknown to it)", () {
      // An older version reads a Rooms section's fields as unknown ones,
      // as this one does on a section type that doesn't use them.
      final json = {
        "id": "favourites",
        "spaces": "all",
        "spaceRows": true,
        "order": "newest",
      };
      final section = HomeSection.fromJson(json)!;
      expect(section.rooms, RoomsFilter.standaloneOnly);
      expect(section.copyWith(collapsed: true).toJson(),
          {...json, "collapsed": true});
    });

    test("the Rooms card keeps its settings in one top-level object", () {
      const card = HomeCard(HomeLayout.otherRooms);
      expect(card.toJson().containsKey("rooms"), isFalse);
      final set = card.copyWith(
          rooms: const RoomsFilter(
              spaces: RoomsFilter.spacesAll, tags: ["u.Work"]),
          name: "Mine");
      final json = set.toJson();
      expect(json["rooms"], {
        "spaces": "all",
        "tags": ["u.Work"],
        "name": "Mine"
      });
      final back = HomeCard.fromJson(json)!;
      expect(back.rooms, set.rooms);
      expect(back.name, "Mine");
      expect(back.toJson(), json);
    });

    test("the untouched old Overview becomes the new default once", () {
      final old = {
        "version": 2,
        "tabs": [
          {
            "id": "overview",
            "name": "Overview",
            "icon": "dashboard",
            "side": [
              {"id": "favourites"},
              {"id": "dms", "collapsed": true},
            ],
            "cards": [
              {"id": "invites"},
              {"id": "recent"},
              {"id": "other_rooms"},
            ],
          }
        ]
      };
      final overview = HomeTabs.parse(old).tab("overview")!;
      expect([for (final s in overview.side) s.type],
          ["favourites", "dms", "standalone"]);
      expect(overview.side[1].collapsed, isTrue);
      expect(overview.side[2].rooms, RoomsFilter.everything);
      // Saved and read again: unchanged (never upgraded twice).
      final again =
          HomeTabs.parse(HomeTabs([overview]).toJson()).tab("overview")!;
      expect(again.toJson(), overview.toJson());
    });

    test("the new default isn't taken for an old one in either direction", () {
      final side = HomeTabs.defaults.tab("overview")!.side;
      // Older versions knew Overviews of two sections; this one has three.
      expect(side.length, 3);
      final rooms = side.last.toJson();
      expect(rooms, {"id": "standalone", "spaces": "all"});
      // A customized Rooms section on an otherwise old Overview is kept.
      final tabs = HomeTabs.parse({
        "version": 2,
        "tabs": [
          {
            "id": "overview",
            "name": "Overview",
            "icon": "dashboard",
            "side": [
              {"id": "favourites"},
              {"id": "dms"},
              {"id": "standalone", "order": "newest"},
            ],
            "cards": [
              {"id": "invites"},
              {"id": "recent"},
              {"id": "other_rooms"},
            ],
          }
        ]
      });
      expect(
          tabs.tab("overview")!.side.last.rooms.order, RoomsFilter.orderNewest);
    });
  });
}
