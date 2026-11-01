import 'dart:convert';
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
      expect([for (final s in overview.side) s.type],
          ["favourites", "dms", "standalone"]);
      expect(_types(overview.main),
          ["invites", "deep_search", "recent", "other_rooms"]);
      final recent = overview.main.card("recent");
      expect(recent.count, 5);
      expect(recent.dms, isTrue);
      expect(recent.muted, isTrue);
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
          ["invites", "deep_search", "recent", "other_rooms"]);
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
          ["favourites", "dms", "standalone"]);
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
      expect(_types(added),
          ["invites", "deep_search", "recent", "other_rooms", "favourites"]);
      // Removing deletes, even step 1's cards (no hidden leftovers).
      final main = added.remove(HomeLayout.favourites);
      expect(main.cards.map((c) => c.id),
          ["invites", "deep_search", "recent", "other_rooms"]);
    });
  });

  group("Earlier defaults", () {
    Map<String, dynamic> saved(Map<String, dynamic> overview) => {
          "version": 2,
          "tabs": [
            overview,
            {"id": "people", "name": "People", "icon": "people"},
          ]
        };
    const oldOverview = {
      "id": "overview",
      "name": "Overview",
      "icon": "dashboard",
      "side": [
        {"id": "favourites", "collapsed": true},
        {"id": "recent"},
      ],
      "cards": [
        {"id": "mentions"},
        {"id": "invites"},
        {"id": "active_now"},
      ],
      "rail": true,
    };

    test("an Overview nobody customized follows today's default", () {
      final tabs = HomeTabs.parse(saved(oldOverview));
      final overview = tabs.tab("overview")!;
      expect([for (final s in overview.side) s.type],
          ["favourites", "dms", "standalone"]);
      expect(_types(overview.main),
          ["invites", "deep_search", "recent", "other_rooms"]);
      // Kept: its sidebar button, a collapsed section both share.
      expect(overview.rail, isTrue);
      expect(overview.side.first.collapsed, isTrue);
      expect(_ids(tabs), ["overview", "people"]);
      // Already current: unchanged.
      final again = HomeTabs.parse(tabs.toJson()).tab("overview")!;
      expect(again.toJson(), overview.toJson());
    });

    test("a customized Overview is kept as it is", () {
      for (final change in <Map<String, dynamic>>[
        {"name": "Start"},
        {"icon": "star"},
        {
          "side": [
            {"id": "recent"},
            {"id": "favourites"},
          ]
        },
        {
          "cards": [
            {"id": "mentions"},
            {"id": "invites"},
          ]
        },
        {
          "cards": [
            {"id": "mentions"},
            {"id": "invites"},
            {"id": "active_now", "hidden": true},
          ]
        },
      ]) {
        final tabs = HomeTabs.parse(saved({...oldOverview, ...change}));
        final overview = tabs.tab("overview")!;
        expect(
            _types(overview.main), isNot(["invites", "recent", "other_rooms"]),
            reason: "$change");
      }
      final renamed = HomeTabs.parse(saved({...oldOverview, "name": "Start"}));
      expect([for (final s in renamed.tab("overview")!.side) s.type],
          ["favourites", "recent"]);
    });

    test("other tabs that look like the old Overview are left alone", () {
      final tabs = HomeTabs.parse(
          saved({...oldOverview, "id": "tab-copy", "rail": null}));
      expect(_types(tabs.tab("tab-copy")!.main),
          ["mentions", "invites", "active_now"]);
    });
  });

  group("Views", () {
    List<String> parts(HomeView v) => [for (final c in v.main.cards) c.part];

    test("People opens on Contacts, with Invites and Blocked after it", () {
      final people = HomeTabs.defaults.tab("people")!;
      expect([for (final v in people.views) v.id],
          ["contacts", "invites", "blocked"]);
      expect([for (final v in people.views) v.name],
          ["Contacts", "Invites", "Blocked"]);
      expect([
        for (final v in people.views) parts(v)
      ], [
        ["contacts"],
        ["invites"],
        ["blocked"]
      ]);
      // Older versions read "cards": view 1, the People page.
      final json = people.toJson();
      expect([for (final c in json["cards"] as List) c["part"]], ["contacts"]);
      expect((json["views"] as List).first,
          {"id": "contacts", "name": "Contacts"});
      // Other tabs have one view, and save no "views".
      final overview = HomeTabs.defaults.tab("overview")!;
      expect(overview.views.length, 1);
      expect(overview.toJson().containsKey("views"), isFalse);
    });

    test("an untouched old People tab gets the views", () {
      final tabs = HomeTabs.parse({
        "version": 2,
        "tabs": [
          {
            "id": "people",
            "name": "People",
            "icon": "people",
            "side": [
              {"id": "dms"}
            ],
            "cards": [
              {"id": "people_page"}
            ],
          }
        ]
      });
      expect([for (final v in tabs.tab("people")!.views) v.id],
          ["contacts", "invites", "blocked"]);
    });

    test("round trip keeps views, their order and unknown fields", () {
      final saved = {
        "tabs": [
          {
            "id": "tab-1",
            "name": "Mine",
            "cards": [
              {"id": "invites"}
            ],
            "views": [
              {
                "id": "a",
                "name": "First",
                "cards": [
                  {"id": "mentions"}
                ]
              },
              {
                "id": "b",
                "name": "  Second  ",
                "cards": [
                  {"id": "dms_page"}
                ],
                "later": 1
              },
              {"id": "b", "name": "Duplicate"},
              {"name": "no id"},
            ],
          }
        ]
      };
      final tab = HomeTabs.parse(saved).tab("tab-1")!;
      expect([for (final v in tab.views) v.id], ["a", "b"]);
      expect([for (final v in tab.views) v.name], ["First", "Second"]);
      // View 1's cards are the tab's "cards".
      expect(_types(tab.views.first.main), ["invites"]);
      expect(_types(tab.view("b")!.main), ["dms_page"]);
      expect(tab.viewHolding(HomeLayout.dmsPage)?.id, "b");
      final again =
          HomeTabs.parse(jsonDecode(jsonEncode(HomeTabs([tab]).toJson())))
              .tab("tab-1")!;
      expect(again.toJson(), tab.toJson());
      expect((tab.toJson()["views"] as List)[1]["later"], 1);
    });

    test("editing a view keeps the others", () {
      final people = HomeTabs.defaults.tab("people")!;
      final invites = people.view("invites")!;
      final edited = people.replaceView(invites.copyWith(name: "Requests"));
      expect([for (final v in edited.views) v.name],
          ["Contacts", "Requests", "Blocked"]);
      final first = edited.replaceView(edited.views.first.copyWith(
          main: const HomeLayout([HomeCard("mentions")], inTab: true)));
      expect(_types(first.main), ["mentions"]);
      expect(first.views.first.name, "Contacts");
      expect(first.views.length, 3);
    });

    test("add, move, rename and remove views", () {
      var tab = HomeTabs.defaults.tab("overview")!;
      expect(tab.views.single.name, "Overview");
      final dms = HomeView(tab.newViewId("dms"),
          name: "Direct messages",
          main: const HomeLayout([HomeCard(HomeLayout.dmsPage)], inTab: true));
      tab = tab.addView(dms);
      expect([for (final v in tab.views) v.id], ["main", "dms"]);
      expect(tab.newViewId("dms"), "dms-2");
      // Moved first: its card becomes the tab's "cards" (what older
      // versions show).
      tab = tab.moveView("dms", 0);
      expect([for (final v in tab.views) v.id], ["dms", "main"]);
      expect(_types(tab.main), ["dms_page"]);
      expect(_types(tab.view("main")!.main),
          ["invites", "deep_search", "recent", "other_rooms"]);
      final saved =
          HomeTabs.parse(jsonDecode(jsonEncode(HomeTabs([tab]).toJson())))
              .tab("overview")!;
      expect(saved.toJson(), tab.toJson());
      tab = tab.renameView("main", "  Cards  ");
      expect(tab.view("main")!.name, "Cards");
      tab = tab.removeView("dms");
      expect([for (final v in tab.views) v.id], ["main"]);
      expect(_types(tab.main),
          ["invites", "deep_search", "recent", "other_rooms"]);
      // Never the last view.
      expect(tab.removeView("main").views.length, 1);
      // Back to one view named like the tab: no "views" saved.
      expect(tab.renameView("main", "Overview").toJson().containsKey("views"),
          isFalse);
    });

    test("People parts: unknown ones show all of it", () {
      String part(Map<String, dynamic> json) => HomeCard.fromJson(json)!.part;
      expect(part({"id": "people_page", "part": "blocked"}), "blocked");
      expect(
          part({"id": "people_page", "part": "nonsense"}), HomeCard.allParts);
      expect(part({"id": "people_page"}), HomeCard.allParts);
      expect(HomeCard.fromJson({"id": "people_page"})!.toJson(),
          isNot(contains("part")));
    });
  });

  group("Editing tabs", () {
    test("every tab can go: Home is then empty, and stays empty", () {
      var tabs = HomeTabs.defaults;
      tabs = tabs.removeTab("people").removeTab("rooms");
      expect(_ids(tabs), ["overview"]);
      expect(tabs.removedDefaults, ["people", "rooms"]);
      expect(tabs.canRemove("overview"), isTrue);
      tabs = tabs.removeTab("overview");
      expect(tabs.tabs, isEmpty);
      expect(tabs.canRemove("overview"), isFalse);
      final saved = jsonDecode(jsonEncode(tabs.toJson()));
      expect(HomeTabs.parse(saved).tabs, isEmpty);
      expect(
          _ids(HomeTabs.parse(saved).reset()), ["overview", "people", "rooms"]);
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
      expect(tab.canAddSection(HomeSection.directMessages), isFalse);
      expect(tab.canAddSection(HomeSection.recent), isTrue);
      expect(tab.canAddSection("nope"), isFalse);
      tab = tab.addSection(HomeSection(tab.newSectionId(HomeSection.recent),
          type: HomeSection.recent));
      final spaceId =
          tab.newSectionId(HomeSection.spaceSection, random: random);
      expect(spaceId, startsWith("space-"));
      tab = tab.addSection(
          HomeSection(spaceId, type: HomeSection.spaceSection, space: "!s"),
          index: 0);
      expect(tab.canAddSection(HomeSection.spaceSection), isTrue);
      expect([for (final s in tab.side) s.type],
          ["space", "favourites", "dms", "standalone", "recent"]);
      tab = tab.moveSection("recent", 0);
      expect([for (final s in tab.side) s.type],
          ["recent", "space", "favourites", "dms", "standalone"]);
      tab = tab.moveSection("recent", 5);
      expect([for (final s in tab.side) s.type],
          ["space", "favourites", "dms", "standalone", "recent"]);
      tab = tab.removeSection(spaceId);
      expect([for (final s in tab.side) s.type],
          ["favourites", "dms", "standalone", "recent"]);
      tab = tab.replaceSection(const HomeSection("dms", collapsed: true));
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
      expect([for (final s in reset.tab("overview")!.side) s.type],
          ["favourites", "dms", "standalone"]);
      expect(_types(reset.tab("overview")!.main),
          ["invites", "deep_search", "recent", "other_rooms"]);
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

  group("Sidebar buttons", () {
    test("unset by default, kept when set, unknown values ignored", () {
      for (final tab in HomeTabs.defaults.tabs) {
        expect(tab.rail, isNull);
        expect(tab.toJson().containsKey("rail"), isFalse);
      }
      final people = HomeTabs.defaultTab(HomeTabs.people)!;
      final off = people.copyWith(rail: false);
      expect(off.rail, isFalse);
      expect(off.toJson()["rail"], isFalse);
      expect(HomeTab.fromJson(off.toJson())!.rail, isFalse);
      expect(HomeTab.fromJson({...off.toJson(), "rail": "yes"})!.rail, isNull);
      expect(HomeTab.fromJson(off.toJson())!.extra, isEmpty);
      // A rename keeps it.
      expect(off.copyWith(name: "Friends").rail, isFalse);
    });

    test("a new tab gets a button when asked", () {
      final (withRail, id) = HomeTabs.defaults
          .createTab(name: "Games", icon: "gamepad", rail: true);
      expect(withRail.tab(id)!.rail, isTrue);
      final (without, other) =
          HomeTabs.defaults.createTab(name: "Work", icon: "work");
      expect(without.tab(other)!.rail, isNull);
      final parsed = HomeTabs.parse(withRail.toJson());
      expect(parsed.tab(id)!.rail, isTrue);
    });
  });
}
