import 'dart:math';

import 'package:commet/ui/organisms/new_home/new_home_cards.dart';
import 'package:commet/ui/organisms/new_home/new_home_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A stand-in room for the card filters.
class _R {
  const _R(this.name, this.minute,
      {this.unread = false,
      this.mention = false,
      this.low = false,
      this.voice = false});
  final String name;
  final int? minute;
  final bool unread;
  final bool mention;
  final bool low;
  final bool voice;
}

DateTime? _time(_R r) => r.minute == null
    ? null
    : DateTime.utc(2026, 10, 22).add(Duration(minutes: r.minute!));

List<String> _names(List<_R> rooms) => rooms.map((r) => r.name).toList();

List<String> _ids(Iterable<HomeCard> cards) => cards.map((c) => c.id).toList();

const _space = HomeCard("space-k3x9qa",
    type: "space",
    space: "!abc:example.org",
    spaceClient: "@me:example.org",
    unreadOnly: true,
    voice: false);

void main() {
  group("Layout schema", () {
    test("a step 1 layout loads and is written back unchanged", () {
      final content = {
        "cards": [
          {"id": "favourites", "hidden": true},
          {
            "id": "recent",
            "hidden": false,
            "count": 10,
            "dms": false,
            "muted": true,
            "unreadOnly": false
          },
          {"id": "other_rooms", "hidden": false},
        ]
      };
      final layout = HomeLayout.parse(content);
      expect(_ids(layout.visible), ["recent", "other_rooms"]);
      expect(layout.toJson(), content);
    });

    test("a new card instance keeps its settings under options", () {
      final layout = HomeLayout.defaults.insert(_space);
      final json = layout.toJson();
      expect((json["cards"] as List).last, {
        "id": "space-k3x9qa",
        "type": "space",
        "hidden": false,
        "options": {
          "space": "!abc:example.org",
          "spaceClient": "@me:example.org",
          "unreadOnly": true,
          "voice": false,
        },
      });
      final again = HomeLayout.parse(json);
      expect(again.cards, layout.cards);
      expect(again.card("space-k3x9qa").type, HomeLayout.spaceCard);
      expect(again.card("space-k3x9qa").space, "!abc:example.org");
    });

    test("a second Recent activity round-trips with its own settings", () {
      final layout = HomeLayout.defaults.insert(const HomeCard("recent-a1b2c3",
          type: "recent", count: 20, dms: false, unreadOnly: true));
      final again = HomeLayout.parse(layout.toJson());
      expect(again.cards, layout.cards);
      expect(again.card("recent").count, 5);
      expect(again.card("recent-a1b2c3").count, 20);
      expect(again.card("recent-a1b2c3").dms, isFalse);
      expect(
          (layout.toJson()["cards"] as List).last,
          containsPair("options", {
            "count": 20,
            "dms": false,
            "muted": true,
            "unreadOnly": true,
          }));
    });

    test("options win over top-level settings; broken options are ignored", () {
      final layout = HomeLayout.parse({
        "cards": [
          {
            "id": "space-1",
            "type": "space",
            "voice": true,
            "options": {"voice": false, "space": "!s:x"}
          },
          {"id": "space-2", "type": "space", "options": "nope"},
        ]
      });
      expect(layout.card("space-1").voice, isFalse);
      expect(layout.card("space-1").space, "!s:x");
      expect(layout.card("space-2").voice, isTrue);
      expect(layout.card("space-2").space, isNull);
    });

    test("unknown card types are kept, written back, and never shown", () {
      final layout = HomeLayout.parse({
        "cards": [
          {"id": "weather-1", "type": "weather", "city": "Lantern Hollow"},
          {"id": "recent"},
        ]
      });
      expect(_ids(layout.visible), ["recent", "favourites", "other_rooms"]);
      expect(layout.hidden, isEmpty);
      expect(layout.canAdd("weather"), isFalse);
      expect(layout.add("weather").cards, layout.cards);
      expect((layout.toJson()["cards"] as List).first, {
        "id": "weather-1",
        "type": "weather",
        "city": "Lantern Hollow",
        "hidden": false,
      });
      // Edits around it leave it where it was.
      final edited = layout.add("unread").moveTo("unread", 0);
      expect(edited.cards.first.id, "weather-1");
    });

    test("duplicate instance ids are dropped on load", () {
      final layout = HomeLayout.parse({
        "cards": [
          {
            "id": "space-1",
            "type": "space",
            "options": {"space": "!a:x"}
          },
          {
            "id": "space-1",
            "type": "space",
            "options": {"space": "!b:x"}
          },
        ]
      });
      expect(layout.cards.where((c) => c.id == "space-1").length, 1);
      expect(layout.card("space-1").space, "!a:x");
    });

    test("type, defaults and settings", () {
      expect(const HomeCard("recent").type, "recent");
      expect(const HomeCard("recent").isDefault, isTrue);
      expect(const HomeCard("recent").configurable, isTrue);
      expect(const HomeCard("unread").isDefault, isFalse);
      expect(const HomeCard("unread").configurable, isFalse);
      expect(_space.configurable, isTrue);
      expect(_space.copyWith(hidden: true).type, "space");
      expect(_space.copyWith(hidden: true).space, "!abc:example.org");
    });
  });

  group("Card library edits", () {
    test("one-off cards use their type as id and can be added once", () {
      final layout = HomeLayout.defaults;
      for (final type in [
        "unread",
        "mentions",
        "invites",
        "active_now",
        "low_priority",
        "contacts"
      ]) {
        expect(layout.canAdd(type), isTrue, reason: type);
        final added = layout.add(type);
        expect(added.visible.last.id, type);
        expect(added.visible.last.type, type);
        expect(added.canAdd(type), isFalse, reason: type);
        expect(added.add(type).cards, added.cards, reason: type);
      }
      expect(layout.canAdd("favourites"), isFalse);
    });

    test("multi-instance cards get unique ids", () {
      var layout = HomeLayout.defaults;
      final random = Random(7);
      for (var i = 0; i < 30; i++) {
        layout = layout.add("recent", random: random);
        layout = layout.add("space", random: random);
      }
      final ids = _ids(layout.cards);
      expect(ids.toSet().length, ids.length);
      expect(layout.cards.where((c) => c.type == "recent").length, 31);
      expect(layout.cards.where((c) => c.type == "space").length, 30);
      for (final c in layout.cards.skip(3)) {
        expect(c.id, matches(RegExp(r"^(recent|space)-[a-z0-9]{6}$")));
      }
      expect(layout.canAdd("recent"), isTrue);
      expect(layout.canAdd("space"), isTrue);
      final again = HomeLayout.parse(layout.toJson());
      expect(again.cards, layout.cards);
    });

    test("newId never reuses an id, even a hidden or unknown one", () {
      final layout = HomeLayout.parse({
        "cards": [
          {"id": "unread", "type": "weather"},
        ]
      });
      expect(layout.newId("unread"), startsWith("unread-"));
      expect(layout.newId("mentions"), "mentions");
    });

    test("add drops into a gap", () {
      final layout = HomeLayout.defaults;
      expect(_ids(layout.add("mentions", gap: 0).visible),
          ["mentions", "recent", "favourites", "other_rooms"]);
      expect(_ids(layout.add("mentions", gap: 1).visible),
          ["recent", "mentions", "favourites", "other_rooms"]);
      expect(_ids(layout.add("mentions").visible),
          ["recent", "favourites", "other_rooms", "mentions"]);
      expect(_ids(layout.add("mentions", gap: 99).visible),
          ["recent", "favourites", "other_rooms", "mentions"]);
    });

    test("removing a step 1 card hides it; adding it brings it back", () {
      final removed = HomeLayout.defaults.remove("favourites");
      expect(_ids(removed.visible), ["recent", "other_rooms"]);
      expect(_ids(removed.hidden), ["favourites"]);
      expect(removed.canAdd("favourites"), isTrue);

      final back = removed.add("favourites", gap: 0);
      expect(_ids(back.visible), ["favourites", "recent", "other_rooms"]);
      expect(back.hidden, isEmpty);
      expect(back.cards.where((c) => c.id == "favourites").length, 1);
    });

    test("removing a hidden Recent activity default brings that one back", () {
      final layout = HomeLayout.defaults
          .replace(const HomeCard("recent", count: 20))
          .remove("recent");
      expect(layout.shows("recent"), isFalse);
      final back = layout.add("recent");
      expect(back.card("recent").count, 20);
      expect(back.cards.where((c) => c.type == "recent").length, 1);
    });

    test("removing a library card deletes it", () {
      final layout = HomeLayout.defaults.add("unread").insert(_space);
      final removed = layout.remove("unread").remove("space-k3x9qa");
      expect(removed.cards, HomeLayout.defaults.cards);
      expect(removed.remove("nothing").cards, removed.cards);
    });

    test("moveTo matches ReorderableListView's newIndex", () {
      final layout = HomeLayout.defaults.add("unread").add("mentions");
      final ids = _ids(layout.visible);
      for (var from = 0; from < ids.length; from++) {
        for (var gap = 0; gap <= ids.length; gap++) {
          final expected = List.of(ids);
          final item = expected.removeAt(from);
          expected.insert(gap > from ? gap - 1 : gap, item);
          expect(_ids(layout.moveTo(ids[from], gap).visible), expected,
              reason: "from $from to gap $gap");
        }
      }
      expect(layout.moveTo("nothing", 0).cards, layout.cards);
    });

    test("moveTo leaves hidden and unknown cards in place", () {
      final layout = HomeLayout.parse({
        "cards": [
          {"id": "recent"},
          {"id": "weather"},
          {"id": "favourites", "hidden": true},
          {"id": "other_rooms"},
        ]
      });
      expect(_ids(layout.moveTo("recent", 2).cards),
          ["weather", "favourites", "other_rooms", "recent"]);
      expect(_ids(layout.moveTo("other_rooms", 0).cards),
          ["other_rooms", "recent", "weather", "favourites"]);
    });

    test("restore defaults keeps unknown top-level fields only", () {
      final layout = HomeLayout.parse({
        "version": 3,
        "cards": [
          {"id": "weather"},
          {"id": "unread"},
          {"id": "recent", "count": 20},
          {"id": "favourites", "hidden": true},
        ]
      }).insert(_space);
      final restored = layout.restoreDefaults();
      expect(restored.cards, HomeLayout.defaults.cards);
      expect(restored.toJson()["version"], 3);
    });

    test("an empty Overview takes drops at gap 0", () {
      var layout = HomeLayout.defaults
          .remove("recent")
          .remove("favourites")
          .remove("other_rooms");
      expect(layout.visible, isEmpty);
      layout = layout.add("contacts", gap: 0);
      expect(_ids(layout.visible), ["contacts"]);
    });
  });

  group("Card summaries", () {
    test("Recent activity", () {
      expect(cardSummary(const HomeCard("recent")),
          "Top 5 · DMs and muted included");
      expect(cardSummary(const HomeCard("recent", count: 10, unreadOnly: true)),
          "Unread only · top 10");
      expect(
          cardSummary(const HomeCard("recent", dms: false)), "Top 5 · no DMs");
      expect(cardSummary(const HomeCard("recent", muted: false)),
          "Top 5 · no muted rooms");
      expect(cardSummary(const HomeCard("recent", dms: false, muted: false)),
          "Top 5 · no DMs or muted rooms");
      expect(cardSummary(const HomeCard("recent-x", type: "recent", count: 20)),
          "Top 20 · DMs and muted included");
    });

    test("Space, and cards without settings", () {
      expect(cardSummary(const HomeCard("space-1", type: "space")),
          "Space · all rooms");
      expect(cardSummary(_space), "Space · unread only · no voice rooms");
      expect(cardSummary(const HomeCard("favourites")), isNull);
      expect(cardSummary(const HomeCard("unread")), isNull);
    });
  });

  group("Card filters", () {
    const rooms = [
      _R("old", 1, low: true),
      _R("pinged", 9, unread: true, mention: true),
      _R("never", null, unread: true),
      _R("new", 10, unread: true),
      _R("mid", 5, low: true, voice: true),
      _R("mid too", 5, voice: true, unread: true),
    ];

    test("newest first is stable and puts rooms without events last", () {
      expect(_names(newestFirst(rooms, _time)),
          ["new", "pinged", "mid", "mid too", "old", "never"]);
    });

    test("Unread, Mentions & highlights and Low priority", () {
      expect(
          _names(roomsWhere(rooms, include: (r) => r.unread, lastEvent: _time)),
          ["new", "pinged", "mid too", "never"]);
      expect(
          _names(
              roomsWhere(rooms, include: (r) => r.mention, lastEvent: _time)),
          ["pinged"]);
      expect(_names(roomsWhere(rooms, include: (r) => r.low, lastEvent: _time)),
          ["mid", "old"]);
      expect(
          roomsWhere(<_R>[], include: (r) => true, lastEvent: _time), isEmpty);
    });

    test("Space: all rooms once, unread only, without voice rooms", () {
      final withDuplicates = [...rooms, rooms[1], rooms[4]];
      List<String> space(HomeCard card) =>
          _names(spaceCardRooms(withDuplicates, card,
              lastEvent: _time,
              isUnread: (r) => r.unread,
              isVoice: (r) => r.voice));

      expect(space(const HomeCard("space-1", type: "space")),
          ["new", "pinged", "mid", "mid too", "old", "never"]);
      expect(space(const HomeCard("space-1", type: "space", unreadOnly: true)),
          ["new", "pinged", "mid too", "never"]);
      expect(space(const HomeCard("space-1", type: "space", voice: false)),
          ["new", "pinged", "old", "never"]);
      expect(space(_space), ["new", "pinged", "never"]);
    });
  });

  group("Card library catalogue", () {
    test("every known card has a library entry, in library order", () {
      expect(CardInfo.all.map((i) => i.type).toList(), HomeLayout.knownTypes);
      for (final info in CardInfo.all) {
        expect(info.label, isNotEmpty);
        expect(info.description, isNotEmpty);
        expect(info.multi, HomeLayout.multiTypes.contains(info.type));
      }
      expect(CardInfo.of("other_rooms").label, "Standalone rooms");
    });

    testWidgets("DashedOutline and DropLine render", (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Column(children: [
            DashedOutline(child: SizedBox(height: 40, child: Text("card"))),
            DropLine(key: Key("drop")),
          ]),
        ),
      ));
      expect(find.text("card"), findsOneWidget);
      expect(find.byKey(const Key("drop")), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
