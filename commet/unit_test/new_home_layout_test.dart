import 'package:commet/ui/organisms/new_home/new_home_layout.dart';
import 'package:flutter_test/flutter_test.dart';

/// A stand-in room for [recentActivity].
class _R {
  const _R(this.name, this.minute,
      {this.dm = false, this.muted = false, this.unread = false});
  final String name;
  final int? minute;
  final bool dm;
  final bool muted;
  final bool unread;
}

List<String> _recent(List<_R> rooms, HomeCard card) => recentActivity<_R>(
      rooms,
      card,
      lastEvent: (r) => r.minute == null
          ? null
          : DateTime.utc(2026, 10, 22).add(Duration(minutes: r.minute!)),
      isDirectMessage: (r) => r.dm,
      isMuted: (r) => r.muted,
      isUnread: (r) => r.unread,
    ).map((r) => r.name).toList();

void main() {
  group("HomeLayout parse", () {
    test("defaults: Recent activity, Favourites, Standalone rooms, all shown",
        () {
      for (final content in [
        null,
        <String, dynamic>{},
        {"cards": "nope"}
      ]) {
        final layout = HomeLayout.parse(content);
        expect(layout.visible.map((c) => c.id),
            ["recent", "favourites", "other_rooms"]);
        expect(layout.hidden, isEmpty);
        final recent = layout.card(HomeLayout.recent);
        expect(recent.count, 5);
        expect(recent.dms, isTrue);
        expect(recent.muted, isTrue);
        expect(recent.unreadOnly, isFalse);
      }
    });

    test("reads order, hidden and Recent activity settings", () {
      final layout = HomeLayout.parse({
        "cards": [
          {"id": "other_rooms"},
          {
            "id": "recent",
            "count": 20,
            "dms": false,
            "muted": false,
            "unreadOnly": true
          },
          {"id": "favourites", "hidden": true},
        ]
      });
      expect(layout.visible.map((c) => c.id), ["other_rooms", "recent"]);
      expect(layout.hidden.map((c) => c.id), ["favourites"]);
      final recent = layout.card("recent");
      expect(recent.count, 20);
      expect(recent.dms, isFalse);
      expect(recent.muted, isFalse);
      expect(recent.unreadOnly, isTrue);
    });

    test("broken fields fall back to the defaults", () {
      final layout = HomeLayout.parse({
        "cards": [
          {"id": "recent", "count": -3, "dms": "yes", "hidden": 1},
          "not a card",
          {"hidden": true},
          {"id": 7},
        ]
      });
      final recent = layout.card("recent");
      expect(recent.count, 5);
      expect(recent.dms, isTrue);
      expect(recent.hidden, isFalse);
      expect(layout.visible.map((c) => c.id),
          ["recent", "favourites", "other_rooms"]);
    });

    test("missing known cards are added at the end; duplicates dropped", () {
      final layout = HomeLayout.parse({
        "cards": [
          {"id": "favourites"},
          {"id": "favourites", "hidden": true},
        ]
      });
      expect(layout.visible.map((c) => c.id),
          ["favourites", "recent", "other_rooms"]);
    });

    test("unknown card ids and fields are kept but not shown", () {
      final content = {
        "version": 2,
        "cards": [
          {"id": "weather", "city": "Lantern Hollow"},
          {"id": "recent", "count": 10, "colour": "teal"},
          {"id": "favourites"},
          {"id": "other_rooms"},
        ]
      };
      final layout = HomeLayout.parse(content);
      expect(layout.visible.map((c) => c.id),
          ["recent", "favourites", "other_rooms"]);
      expect(layout.hidden, isEmpty);

      final json = layout.toJson();
      expect(json["version"], 2);
      final cards = json["cards"] as List;
      expect(cards.first,
          {"id": "weather", "city": "Lantern Hollow", "hidden": false});
      expect((cards[1] as Map)["colour"], "teal");
      expect((cards[1] as Map)["count"], 10);
    });
  });

  group("HomeLayout serialize", () {
    test("round trip", () {
      final layout = HomeLayout.defaults
          .replace(const HomeCard("recent",
              count: 10, dms: false, muted: true, unreadOnly: true))
          .hide("favourites")
          .move("other_rooms", -1);
      final again = HomeLayout.parse(layout.toJson());
      expect(again.cards, layout.cards);
    });

    test("defaults serialize to the documented shape", () {
      expect(HomeLayout.defaults.toJson(), {
        "cards": [
          {
            "id": "recent",
            "hidden": false,
            "count": 5,
            "dms": true,
            "muted": true,
            "unreadOnly": false
          },
          {"id": "favourites", "hidden": false},
          {"id": "other_rooms", "hidden": false},
        ]
      });
    });
  });

  group("HomeLayout edits", () {
    test("move up and down, disabled at the ends", () {
      final layout = HomeLayout.defaults;
      expect(layout.canMoveUp("recent"), isFalse);
      expect(layout.canMoveDown("recent"), isTrue);
      expect(layout.canMoveDown("other_rooms"), isFalse);
      expect(layout.move("recent", -1).cards, layout.cards);

      final moved = layout.move("recent", 1);
      expect(moved.visible.map((c) => c.id),
          ["favourites", "recent", "other_rooms"]);
      expect(moved.move("recent", -1).cards, layout.cards);
    });

    test("moving skips hidden and unknown cards", () {
      final layout = HomeLayout.parse({
        "cards": [
          {"id": "recent"},
          {"id": "weather"},
          {"id": "favourites", "hidden": true},
          {"id": "other_rooms"},
        ]
      });
      expect(layout.canMoveDown("recent"), isTrue);
      final moved = layout.move("other_rooms", -1);
      expect(moved.cards.map((c) => c.id),
          ["other_rooms", "weather", "favourites", "recent"]);
      expect(moved.visible.map((c) => c.id), ["other_rooms", "recent"]);
    });

    test("hide and add back", () {
      final layout = HomeLayout.defaults.hide("favourites").hide("other_rooms");
      expect(layout.visible.map((c) => c.id), ["recent"]);
      expect(layout.hidden.length, 2);
      final back = layout.showAll();
      expect(back.hidden, isEmpty);
      expect(back.visible.map((c) => c.id),
          ["recent", "favourites", "other_rooms"]);
    });
  });

  group("Recent activity", () {
    const rooms = [
      _R("old", 1),
      _R("dm", 9, dm: true, unread: true),
      _R("muted", 8, muted: true),
      _R("never", null),
      _R("new", 10, unread: true),
      _R("mid", 5),
      _R("mid too", 5),
    ];

    test("defaults: everything with an event, newest first, top 5", () {
      expect(_recent(rooms, const HomeCard("recent")),
          ["new", "dm", "muted", "mid", "mid too"]);
    });

    test("count", () {
      expect(_recent(rooms, const HomeCard("recent", count: 10)),
          ["new", "dm", "muted", "mid", "mid too", "old"]);
    });

    test("without DMs, without muted rooms, unread only", () {
      expect(_recent(rooms, const HomeCard("recent", dms: false)),
          ["new", "muted", "mid", "mid too", "old"]);
      expect(_recent(rooms, const HomeCard("recent", muted: false)),
          ["new", "dm", "mid", "mid too", "old"]);
      expect(_recent(rooms, const HomeCard("recent", unreadOnly: true)),
          ["new", "dm"]);
      expect(
          _recent(
              rooms, const HomeCard("recent", unreadOnly: true, dms: false)),
          ["new"]);
    });
  });
}
