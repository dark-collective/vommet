// Vommet: the unified chat list's pure logic (Vommet issue 291): building
// and sorting rows, space aggregation, search, the space pane and drill-in
// navigation. Made-up names.
import 'package:commet/ui/organisms/unified_chat_list/unified_chat_model.dart';
import 'package:commet/ui/organisms/unified_chat_list/unified_chat_source.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 10, 15, 12);

ChatEntry chat(String id,
        {int? minutesAgo,
        ChatKind kind = ChatKind.room,
        int unread = 0,
        int mentions = 0,
        bool muted = false,
        bool favorite = false,
        int voice = 0}) =>
    ChatEntry(
      key: "acct:$id",
      roomId: id,
      name: id,
      kind: kind,
      lastActivity: minutesAgo == null
          ? null
          : _now.subtract(Duration(minutes: minutesAgo)),
      preview: "hi from $id",
      unread: unread,
      mentions: mentions,
      muted: muted,
      favorite: favorite,
      voiceCount: voice,
    );

SpaceEntry space(String id,
        {List<ChatEntry> rooms = const [],
        List<SpaceEntry> subspaces = const [],
        List<ChatPreviewEntry> previews = const [],
        int? members}) =>
    SpaceEntry(
        key: "acct:$id",
        spaceId: id,
        name: id,
        rooms: rooms,
        subspaces: subspaces,
        previews: previews,
        memberCount: members);

List<String> keys(List<TopRow> rows) => rows.map((r) => r.roomId).toList();

void main() {
  group("buildTopRows", () {
    test("newest first, chats with no activity last", () {
      final rows = buildTopRows(
        directMessages: [chat("juniper", minutesAgo: 5)],
        rooms: [chat("inkwell", minutesAgo: 30), chat("quiet")],
        spaces: [
          space("lantern", rooms: [chat("general", minutesAgo: 1)])
        ],
      );
      expect(keys(rows), ["lantern", "juniper", "inkwell", "quiet"]);
    });

    test("a room inside a space never gets its own row, even a DM", () {
      final general = chat("general", minutesAgo: 1);
      final dm = chat("rowan", minutesAgo: 2, kind: ChatKind.direct);
      final maps = chat("maps", minutesAgo: 3);
      final rows = buildTopRows(
        directMessages: [dm],
        rooms: [general, maps],
        spaces: [
          space("lantern", rooms: [
            general,
            dm
          ], subspaces: [
            space("archives", rooms: [maps])
          ])
        ],
      );
      expect(keys(rows), ["lantern"]);
    });

    test("a chat listed as DM and room appears once", () {
      final dm = chat("tess", minutesAgo: 1, kind: ChatKind.direct);
      final rows = buildTopRows(directMessages: [dm], rooms: [dm]);
      expect(keys(rows), ["tess"]);
    });

    test("a subspace listed as a top-level space shows only in its parent", () {
      final archives = space("archives", rooms: [chat("maps", minutesAgo: 1)]);
      final rows = buildTopRows(spaces: [
        space("lantern", subspaces: [archives]),
        archives,
      ]);
      expect(keys(rows), ["lantern"]);
    });

    test("pinned chats first, in their saved order", () {
      final rows = buildTopRows(
        directMessages: [
          chat("juniper", minutesAgo: 1),
          chat("pebble", minutesAgo: 900),
        ],
        rooms: [
          chat("inkwell", minutesAgo: 2),
          chat("quests", minutesAgo: 50),
        ],
        spaces: [
          space("harbor", rooms: [chat("patch", minutesAgo: 3)])
        ],
        pins: {"quests": "b", "pebble": "a", "harbor": null},
      );
      expect(keys(rows), ["pebble", "quests", "harbor", "juniper", "inkwell"]);
      expect(rows.take(3).every((r) => r.pinned), isTrue);
      expect(rows.skip(3).any((r) => r.pinned), isFalse);
    });

    test("favorites come right after the pins (Vommet issue 541)", () {
      final rows = buildTopRows(
        directMessages: [
          chat("juniper", minutesAgo: 1),
          chat("pebble", minutesAgo: 900, favorite: true),
        ],
        rooms: [
          chat("inkwell", minutesAgo: 2, favorite: true),
          chat("quests", minutesAgo: 50),
          chat("lantern", minutesAgo: 70, favorite: true),
        ],
        pins: {"lantern": "a"},
      );
      expect(keys(rows), ["lantern", "inkwell", "pebble", "juniper", "quests"]);
      expect(rows.map((r) => r.favorite), [true, true, true, false, false]);
    });

    test("pins for rooms that aren't listed are ignored", () {
      final rows = buildTopRows(
          rooms: [chat("inkwell", minutesAgo: 2)], pins: {"gone": "a"});
      expect(keys(rows), ["inkwell"]);
    });
  });

  group("SpaceDigest", () {
    final lantern = space("lantern", rooms: [
      chat("general", minutesAgo: 10, unread: 9, mentions: 1),
      chat("tabletop", kind: ChatKind.voice, voice: 2),
      chat("sketchbook", minutesAgo: 20, unread: 5),
      chat("spoilers", minutesAgo: 5, unread: 7, muted: true),
    ], subspaces: [
      space("archives", rooms: [
        chat("maps", minutesAgo: 1, unread: 2),
        chat("lore", minutesAgo: 600),
      ])
    ]);

    test("the newest room comes from any depth", () {
      final digest = SpaceDigest.of(lantern);
      expect(digest.latest?.roomId, "maps");
      expect(digest.lastActivity, _now.subtract(const Duration(minutes: 1)));
    });

    test("chips are most recently active first, quiet rooms last", () {
      final digest = SpaceDigest.of(lantern, maxChips: 4);
      expect(digest.chips.map((c) => c.roomId),
          ["maps", "spoilers", "general", "sketchbook"]);
    });

    test("unread sums rooms that aren't muted; mentions from all", () {
      final digest = SpaceDigest.of(lantern);
      expect(digest.unread, 9 + 5 + 2);
      expect(digest.mentions, 1);
    });

    test("the busiest voice room is reported", () {
      final digest = SpaceDigest.of(space("s", rooms: [
        chat("v1", kind: ChatKind.voice, voice: 1),
        chat("v2", kind: ChatKind.voice, voice: 3),
      ]));
      expect(digest.voice?.roomId, "v2");
      expect(SpaceDigest.of(space("e")).voice, isNull);
    });

    test("an empty space has no latest message", () {
      final digest = SpaceDigest.of(space("quiet", rooms: [chat("a")]));
      expect(digest.latest, isNull);
      expect(digest.lastActivity, isNull);
      expect(digest.roomCount, 1);
    });

    test("a looping hierarchy counts each room once", () {
      final rooms = [chat("a", minutesAgo: 1, unread: 1)];
      final inner = space("inner", rooms: rooms);
      final outer = space("outer", rooms: rooms, subspaces: [
        inner,
        space("outer", rooms: rooms),
      ]);
      expect(outer.allRooms.length, 1);
      expect(SpaceDigest.of(outer).unread, 1);
    });
  });

  group("filterTopRows", () {
    final rows = buildTopRows(
      directMessages: [chat("Juniper Vale", minutesAgo: 1)],
      spaces: [
        space("Lantern Hollow", rooms: [chat("sketchbook", minutesAgo: 2)])
      ],
    );

    test("matches names, ignoring case", () {
      expect(keys(filterTopRows(rows, "juni")), ["Juniper Vale"]);
    });

    test("a space matches by one of its rooms", () {
      expect(keys(filterTopRows(rows, "SKETCH")), ["Lantern Hollow"]);
    });

    test("an empty query keeps everything", () {
      expect(filterTopRows(rows, "  ").length, 2);
    });
  });

  test("the space pane lists rooms, then unjoined rooms, then subspaces", () {
    final rows = buildSpacePaneRows(space("lantern",
        rooms: [chat("general"), chat("tabletop", kind: ChatKind.voice)],
        previews: [const ChatPreviewEntry(roomId: "x", name: "lounge")],
        subspaces: [space("archives")]));
    expect(rows.map((r) => r.runtimeType), [
      SpaceRoomRow,
      SpaceRoomRow,
      SpacePreviewRow,
      SubspaceRow,
    ]);
  });

  test("spaceSubtitle-style counts include subspace rooms", () {
    final s = space("lantern", members: 38, rooms: [
      chat("a")
    ], subspaces: [
      space("b", rooms: [chat("c"), chat("d")])
    ]);
    expect(SpaceDigest.of(s).roomCount, 3);
  });

  group("SpaceNavigation", () {
    test("open, drill in, back up and close", () {
      final nav = SpaceNavigation();
      var changes = 0;
      nav.addListener(() => changes++);

      nav.openRoot("lantern");
      expect(nav.path, ["lantern"]);
      expect(nav.parent, isNull);

      nav.drillInto("archives");
      expect(nav.path, ["lantern", "archives"]);
      expect(nav.current, "archives");
      expect(nav.parent, "lantern");

      nav.back();
      expect(nav.path, ["lantern"]);
      nav.back();
      expect(nav.isOpen, isFalse);
      expect(changes, 4);
    });

    test("coming back to a space returns to the subspace last open there", () {
      final nav = SpaceNavigation()
        ..openRoot("lantern")
        ..drillInto("archives")
        ..openRoot("harbor");
      expect(nav.path, ["harbor"]);

      nav.openRoot("lantern");
      expect(nav.path, ["lantern", "archives"]);

      nav.close();
      nav.openRoot("lantern");
      expect(nav.path, ["lantern", "archives"]);
    });

    test("backing out to the top level is remembered too", () {
      final nav = SpaceNavigation()
        ..openRoot("lantern")
        ..drillInto("archives")
        ..back()
        ..openRoot("harbor")
        ..openRoot("lantern");
      expect(nav.path, ["lantern"]);
    });

    test("opening the open space again changes nothing", () {
      final nav = SpaceNavigation()
        ..openRoot("lantern")
        ..drillInto("archives");
      nav.openRoot("lantern");
      expect(nav.path, ["lantern", "archives"]);
    });

    test("drilling into a space already on the path goes back to it", () {
      final nav = SpaceNavigation()
        ..openRoot("a")
        ..drillInto("b")
        ..drillInto("c")
        ..drillInto("b");
      expect(nav.path, ["a", "b"]);
    });

    test("drilling in does nothing while closed", () {
      final nav = SpaceNavigation()..drillInto("b");
      expect(nav.isOpen, isFalse);
    });

    test("prune drops spaces that are gone", () {
      final nav = SpaceNavigation()
        ..openRoot("a")
        ..drillInto("b")
        ..drillInto("c");
      nav.prune((path) => !path.contains("c"));
      expect(nav.path, ["a", "b"]);
      nav.prune((path) => path.first != "a");
      expect(nav.isOpen, isFalse);
      nav.openRoot("a");
      expect(nav.path, ["a"]);
    });
  });

  test("isValidSpacePath follows the subspace chain from a top-level row", () {
    final rows = buildTopRows(spaces: [
      space("lantern", subspaces: [
        space("archives", subspaces: [space("old")])
      ])
    ]);
    expect(isValidSpacePath(rows, ["acct:lantern"]), isTrue);
    expect(
        isValidSpacePath(rows, ["acct:lantern", "acct:archives", "acct:old"]),
        isTrue);
    expect(isValidSpacePath(rows, ["acct:archives"]), isFalse);
    expect(isValidSpacePath(rows, ["acct:lantern", "acct:old"]), isFalse);
    expect(isValidSpacePath(rows, []), isFalse);
  });

  test("readPinnedRooms reads the sidebar pins account data", () {
    expect(
        readPinnedRooms({
          "rooms": {
            "!a:x": {"order": "m"},
            "!b:x": {},
            "!c:x": "junk",
          }
        }),
        {"!a:x": "m", "!b:x": null, "!c:x": null});
    expect(readPinnedRooms(null), isEmpty);
    expect(readPinnedRooms({"rooms": "nope"}), isEmpty);
  });

  group("formatChatTime", () {
    final now = DateTime(2026, 10, 15, 18, 30);

    test("today shows the time", () {
      expect(
          formatChatTime(DateTime(2026, 10, 15, 9, 35), now,
              use24HourFormat: true),
          "09:35");
      // intl puts a narrow no-break space before AM/PM.
      expect(formatChatTime(DateTime(2026, 10, 15, 9, 35), now),
          matches(RegExp(r"^9:35\sAM$")));
    });

    test("yesterday, then weekdays, then dates", () {
      expect(formatChatTime(DateTime(2026, 10, 14, 23), now), "Yesterday");
      expect(formatChatTime(DateTime(2026, 10, 12, 8), now), "Mon");
      expect(formatChatTime(DateTime(2026, 9, 30, 8), now), "Sep 30");
      expect(formatChatTime(DateTime(2025, 9, 30, 8), now), "Sep 30, 2025");
    });

    test("a time in the future counts as today", () {
      expect(
          formatChatTime(DateTime(2026, 10, 15, 19), now,
              use24HourFormat: true),
          "19:00");
    });
  });
}
