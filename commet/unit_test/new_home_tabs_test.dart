import 'dart:math';

import 'package:commet/ui/organisms/new_home/new_home_layout.dart';
import 'package:commet/ui/organisms/new_home/new_home_tabs.dart';
import 'package:flutter_test/flutter_test.dart';

/// A stand-in room for [sideListRooms].
class _R {
  const _R(this.name, this.minute,
      {this.favourite = false,
      this.dm = false,
      this.voice = false,
      this.live = false,
      this.photos = false,
      this.standalone = false,
      this.low = false});
  final String name;
  final int? minute;
  final bool favourite;
  final bool dm;
  final bool voice;
  final bool live;
  final bool photos;
  final bool standalone;
  final bool low;

  @override
  String toString() => name;
}

List<List<String>> _side(List<HomeSection> sections, List<_R> rooms,
        {Map<String, List<_R>> spaces = const {}}) =>
    sideListRooms<_R>(
      sections,
      rooms,
      SideListFacts(
        lastEvent: (r) => r.minute == null
            ? null
            : DateTime.utc(2026, 10, 22).add(Duration(minutes: r.minute!)),
        isFavourite: (r) => r.favourite,
        isDirectMessage: (r) => r.dm,
        isVoice: (r) => r.voice,
        isLive: (r) => r.live,
        isPhotos: (r) => r.photos,
        isStandalone: (r) => r.standalone,
        isLowPriority: (r) => r.low,
        spaceRooms: (s) => spaces[s.space],
      ),
    ).map((list) => list.map((r) => r.name).toList()).toList();

List<String> _ids(HomeTabs tabs) => [for (final t in tabs.tabs) t.id];

List<String> _types(HomeLayout main) => [for (final c in main.cards) c.type];

void main() {
  group("Defaults", () {
    test("Overview, People and Rooms with the approved contents", () {
      final tabs = HomeTabs.defaults;
      expect(_ids(tabs), ["overview", "people", "rooms"]);
      final overview = tabs.tab("overview")!;
      expect([for (final s in overview.side) s.type], ["favourites", "recent"]);
      expect(_types(overview.main), ["mentions", "invites", "active_now"]);
      final people = tabs.tab("people")!;
      expect([for (final s in people.side) s.type], ["dms"]);
      expect(_types(people.main), ["people_page"]);
      final rooms = tabs.tab("rooms")!;
      expect([for (final s in rooms.side) s.type],
          ["live_voice", "standalone", "low_priority"]);
      expect([for (final s in rooms.side) s.collapsed], [false, false, true]);
      expect(_types(rooms.main), ["rooms_page"]);
    });

    test("whole pages: People and the Rooms browser each have a home", () {
      final tabs = HomeTabs.defaults;
      expect(tabs.tabHolding(HomeLayout.peoplePage)?.id, "people");
      expect(tabs.tabHolding(HomeLayout.roomsPage)?.id, "rooms");
    });
  });

  group("Parse and migrate", () {
    test("nothing saved: the defaults", () {
      for (final content in [
        null,
        <String, dynamic>{},
        {"tabs": []},
        {"tabs": "broken"},
        {
          "tabs": [
            {"name": "no id"}
          ]
        },
      ]) {
        expect(_ids(HomeTabs.parse(content)), ["overview", "people", "rooms"]);
      }
    });

    test("an untouched old Overview gets the new defaults", () {
      final old = HomeLayout.defaults.toJson();
      final tabs = HomeTabs.parse(old);
      expect(_types(tabs.tab("overview")!.main),
          ["mentions", "invites", "active_now"]);
      // The old layout stays for older Vommets.
      expect(tabs.toJson()["cards"], old["cards"]);
      expect(tabs.toJson()["version"], 2);
    });

    test("a customized old Overview keeps its cards, hidden ones dropped", () {
      final old = {
        "cards": [
          {"id": "mentions", "hidden": false},
          {"id": "recent", "hidden": false, "count": 10},
          {"id": "favourites", "hidden": true},
          {"id": "other_rooms", "hidden": true},
          {
            "id": "space-abc123",
            "type": "space",
            "hidden": false,
            "options": {"space": "!s:x.org"}
          },
          {"id": "future_card", "hidden": false, "x": 1},
        ]
      };
      final tabs = HomeTabs.parse(old);
      final main = tabs.tab("overview")!.main;
      expect([for (final c in main.cards) c.id],
          ["mentions", "recent", "space-abc123", "future_card"]);
      expect(main.card("recent").count, 10);
      expect(main.inTab, isTrue);
      // Overview's side list and the other tabs are the defaults.
      expect([for (final s in tabs.tab("overview")!.side) s.type],
          ["favourites", "recent"]);
      expect(_ids(tabs), ["overview", "people", "rooms"]);
    });

    test("an old Overview with only a setting changed counts as customized",
        () {
      final tabs = HomeTabs.parse({
        "cards": [
          {"id": "recent", "count": 20},
          {"id": "favourites"},
          {"id": "other_rooms"},
        ]
      });
      expect(_types(tabs.tab("overview")!.main),
          ["recent", "favourites", "other_rooms"]);
    });

    test("round trip keeps unknown tabs' fields and unknown sections", () {
      final content = {
        "version": 2,
        "later": {"a": 1},
        "cards": [
          {"id": "recent"}
        ],
        "tabs": [
          {
            "id": "tab-aaaaaa",
            "name": "Gaming",
            "icon": "gamepad",
            "colour": "red",
            "side": [
              {"id": "future", "type": "future_section", "z": 2},
              {
                "id": "space-bbbbbb",
                "type": "space",
                "space": "!g:x.org",
                "spaceClient": "@me:x.org",
                "collapsed": true
              },
            ],
            "cards": [
              {"id": "rooms_page"}
            ]
          },
        ],
      };
      final tabs = HomeTabs.parse(content);
      final tab = tabs.tab("tab-aaaaaa")!;
      expect(tab.name, "Gaming");
      expect(tab.sections.map((s) => s.id), ["space-bbbbbb"]);
      expect(tab.side.length, 2);
      final json = tabs.toJson();
      expect(json["later"], {"a": 1});
      expect(json["cards"], content["cards"]);
      final back = (json["tabs"] as List).single as Map;
      expect(back["colour"], "red");
      expect((back["side"] as List).first, {
        "id": "future",
        "type": "future_section",
        "z": 2,
      });
      expect(HomeTabs.parse(json).toJson(), json);
    });

    test("duplicate tab and section ids keep the first", () {
      final tabs = HomeTabs.parse({
        "tabs": [
          {
            "id": "a",
            "name": "A",
            "side": [
              {"id": "recent"},
              {"id": "recent", "collapsed": true},
            ]
          },
          {"id": "a", "name": "B"},
        ]
      });
      expect(_ids(tabs), ["a"]);
      expect(tabs.tab("a")!.side.single.collapsed, isFalse);
    });

    test("a tab's main page doesn't get step 1's cards back", () {
      final tabs = HomeTabs.parse({
        "tabs": [
          {"id": "a", "name": "A", "cards": []}
        ]
      });
      expect(tabs.tab("a")!.main.cards, isEmpty);
      final added =
          HomeTabs.defaults.tab("overview")!.main.add(HomeLayout.favourites);
      expect(
          _types(added), ["mentions", "invites", "active_now", "favourites"]);
      // Removing deletes, even step 1's cards (no hidden leftovers).
      final main = added.remove(HomeLayout.favourites);
      expect(
          main.cards.map((c) => c.id), ["mentions", "invites", "active_now"]);
    });
  });

  group("Editing tabs", () {
    test("at least one tab", () {
      var tabs = HomeTabs.defaults;
      tabs = tabs.removeTab("people").removeTab("rooms");
      expect(_ids(tabs), ["overview"]);
      expect(tabs.canRemove("overview"), isFalse);
      expect(_ids(tabs.removeTab("overview")), ["overview"]);
      expect(tabs.removedDefaults, ["people", "rooms"]);
    });

    test("move, shift, duplicate and new tabs", () {
      final random = Random(1);
      var tabs = HomeTabs.defaults;
      expect(
          _ids(tabs.moveTab("overview", 3)), ["people", "rooms", "overview"]);
      expect(_ids(tabs.moveTab("rooms", 0)), ["rooms", "overview", "people"]);
      expect(
          _ids(tabs.shiftTab("people", -1)), ["people", "overview", "rooms"]);
      expect(_ids(tabs.shiftTab("overview", -1)), _ids(tabs));
      tabs = tabs.duplicateTab("people", random: random);
      final copy = tabs.tabs[2];
      expect(copy.id, startsWith("tab-"));
      expect(copy.name, "People copy");
      expect(_types(copy.main), ["people_page"]);
      final fresh = tabs.newTab("  Gaming  ", "gamepad", random: random);
      expect(fresh.name, "Gaming");
      expect(fresh.side, isEmpty);
      expect(fresh.main.cards, isEmpty);
      expect(HomeTabs.cleanName(""), "New tab");
      expect(HomeTabs.cleanName("x" * 60).length, HomeTabs.maxName);
    });

    test("sections: add once (spaces many times), move, remove", () {
      final random = Random(2);
      var tab = HomeTabs.defaults.tab("overview")!;
      expect(tab.canAddSection(HomeSection.recent), isFalse);
      expect(tab.canAddSection(HomeSection.directMessages), isTrue);
      expect(tab.canAddSection("nope"), isFalse);
      tab = tab.addSection(HomeSection(
          tab.newSectionId(HomeSection.directMessages),
          type: HomeSection.directMessages));
      final spaceId =
          tab.newSectionId(HomeSection.spaceSection, random: random);
      expect(spaceId, startsWith("space-"));
      tab = tab.addSection(
          HomeSection(spaceId, type: HomeSection.spaceSection, space: "!s"),
          index: 0);
      expect(tab.canAddSection(HomeSection.spaceSection), isTrue);
      expect([for (final s in tab.side) s.type],
          ["space", "favourites", "recent", "dms"]);
      tab = tab.moveSection("dms", 0);
      expect([for (final s in tab.side) s.type],
          ["dms", "space", "favourites", "recent"]);
      tab = tab.moveSection("dms", 4);
      expect([for (final s in tab.side) s.type],
          ["space", "favourites", "recent", "dms"]);
      tab = tab.removeSection(spaceId);
      expect(
          [for (final s in tab.side) s.type], ["favourites", "recent", "dms"]);
      tab = tab.replaceSection(const HomeSection("recent", collapsed: true));
      expect(tab.side[1].collapsed, isTrue);
    });

    test("New tab: empty, a copy, or a removed default tab", () {
      final random = Random(3);
      var tabs = HomeTabs.defaults.removeTab("people");
      final (empty, emptyId) = tabs.createTab(
          name: "Gaming", icon: "gamepad", after: "overview", random: random);
      expect(_ids(empty), ["overview", emptyId, "rooms"]);
      expect(empty.tab(emptyId)!.side, isEmpty);
      expect(empty.tab(emptyId)!.main.cards, isEmpty);

      final (copy, copyId) =
          tabs.createTab(name: "Mine", icon: "star", copyOf: "rooms");
      expect(_ids(copy).last, copyId);
      expect([for (final s in copy.tab(copyId)!.side) s.type],
          ["live_voice", "standalone", "low_priority"]);
      expect(_types(copy.tab(copyId)!.main), ["rooms_page"]);

      final (back, backId) =
          tabs.createTab(name: "Friends", icon: "heart", restore: "people");
      expect(backId, "people");
      expect(back.tab("people")!.name, "Friends");
      expect(back.tabHolding(HomeLayout.peoplePage)?.id, "people");
      expect(back.removedDefaults, isEmpty);

      // A default tab that's still there isn't restored twice.
      final (again, againId) =
          back.createTab(name: "X", icon: "tag", restore: "people");
      expect(againId, isNot("people"));
      expect(again.tab(againId)!.side, isEmpty);
    });

    test("reset brings the defaults back and keeps unknown fields", () {
      final tabs = HomeTabs.parse({
        "later": true,
        "tabs": [
          {"id": "tab-x", "name": "Mine"}
        ]
      });
      final reset = tabs.reset();
      expect(_ids(reset), ["overview", "people", "rooms"]);
      expect(reset.toJson()["later"], true);
    });
  });

  group("Side list", () {
    const fav = _R("fav", 5, favourite: true, standalone: true);
    const dm = _R("dm", 9, dm: true);
    const quiet = _R("quiet", null, standalone: true);
    const call = _R("call", 1, voice: true, live: true);
    const voice = _R("voice", 3, voice: true);
    const album = _R("album", 2, photos: true);
    const low = _R("low", 8, standalone: true, low: true);
    const spaced = _R("spaced", 7);
    const rooms = [fav, dm, quiet, call, voice, album, low, spaced];

    test("Overview: favourites, then everything else by activity", () {
      expect(
          _side([
            const HomeSection(HomeSection.favourites),
            const HomeSection(HomeSection.recent),
          ], rooms),
          [
            ["fav"],
            ["dm", "low", "spaced", "voice", "album", "call"],
          ]);
    });

    test("each room once: the first section wins", () {
      expect(
          _side([
            const HomeSection(HomeSection.recent),
            const HomeSection(HomeSection.favourites),
            const HomeSection(HomeSection.directMessages),
          ], rooms),
          [
            ["dm", "low", "spaced", "fav", "voice", "album", "call"],
            [],
            [],
          ]);
    });

    test("Rooms: live calls, standalone, low priority keeps its rooms", () {
      expect(
          _side([
            const HomeSection(HomeSection.liveVoice),
            const HomeSection(HomeSection.standalone),
            const HomeSection(HomeSection.lowPriority, collapsed: true),
          ], rooms),
          [
            ["call"],
            ["fav", "quiet"],
            ["low"],
          ]);
    });

    test("kinds and spaces", () {
      expect(
          _side(
              [
                const HomeSection(HomeSection.voice),
                const HomeSection(HomeSection.photos),
                const HomeSection("space-a",
                    type: HomeSection.spaceSection, space: "!a"),
                const HomeSection("space-gone",
                    type: HomeSection.spaceSection, space: "!gone"),
                const HomeSection("future", type: "future"),
              ],
              rooms,
              spaces: {
                "!a": [spaced, voice, const _R("not joined", 4)],
              }),
          [
            ["voice", "call"],
            ["album"],
            ["spaced"],
            [],
            [],
          ]);
    });
  });
}
