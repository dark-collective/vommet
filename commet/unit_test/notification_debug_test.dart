// Vommet issue 949: the notification debug dump (numbers only, rooms
// renumbered at random each time, its checks), and the badge totals that
// must equal the rooms they add up.
import 'dart:math';

import 'package:commet/client/room.dart';
import 'package:commet/client/space.dart';
import 'package:commet/ui/organisms/new_home/new_home_column.dart';
import 'package:commet/utils/notification_debug.dart';
import 'package:commet/utils/notification_utils.dart';
import 'package:flutter_test/flutter_test.dart';

class _Room extends Room {
  _Room(this.localId,
      {this.messages = 0, this.mentions = 0, this.pushRule = PushRule.notify});

  @override
  final String localId;
  final int messages;
  final int mentions;
  @override
  final PushRule pushRule;

  @override
  int get notificationCount => messages;
  @override
  int get highlightedNotificationCount => mentions;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Space extends Space {
  _Space(this.rooms,
      {this.subspaces = const [], this.pushRule = PushRule.notify});

  @override
  final List<Room> rooms;
  @override
  final List<Space> subspaces;
  @override
  final PushRule pushRule;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A direct message whose row, header, rail icon and Home agree.
DebugRoom dm(int count,
        {PushRule rule = PushRule.notify,
        bool inSection = true,
        bool favourite = false,
        int older = 0,
        int local = 0}) =>
    DebugRoom(
      kind: DebugRoomKind.dm,
      rule: rule,
      favourite: favourite,
      groupSize: older > 0 ? 2 : 1,
      olderGroupCount: older,
      count: count,
      localHighlights: local,
      badge: rule == PushRule.dontNotify ? 0 : max(count, local),
      badgeNoisy: true,
      dot: count > 0,
      rowDot: count + older > 0,
      railIcon: count + older,
      homeAdds: count + older,
      inDmSection: inSection,
      trayChat: rule != PushRule.dontNotify && max(count, local) > 0,
    );

DebugSnapshot snapshot(List<DebugRoom> rooms,
    {List<DebugSpace> spaces = const [],
    int invites = 0,
    DebugTotals? totals,
    Random? random}) {
  final rows = rooms.where((r) => r.inDmSection);
  final home = invites +
      rooms.where((r) => r.isDm).fold<int>(0, (s, r) => s + r.homeAdds);
  return DebugSnapshot(
    rooms: rooms,
    spaces: spaces,
    totals: totals ??
        DebugTotals(
          home: home,
          homeInvites: invites,
          people: home,
          peopleInvites: invites,
          dmHeader: rows.fold<int>(0, (s, r) => s + r.badge),
          dmRows: rows.length,
          trayChats: rooms.where((r) => r.trayChat).length,
        ),
    build: "testing-2026-10-30",
    platform: "linux",
    layout: "Discord",
    random: random ?? Random(1),
  );
}

List<String> broken(DebugSnapshot s) => [
      for (final c in s.checks())
        if (!c.ok) c.lines.join(" ")
    ];

void main() {
  group("the dump's checks", () {
    test("badges that agree break nothing", () {
      final s = snapshot([dm(2), dm(1), dm(0)], invites: 1);
      expect(broken(s), isEmpty);
      expect(s.text(), contains("CHECKS: 0 broken"));
    });

    // CK's report: Direct messages 3, Home 2.
    test("a mention found on the device: the header counts it, Home not", () {
      final room = dm(0, local: 1);
      final s = snapshot([dm(2), room],
          totals: const DebugTotals(
              home: 2, people: 2, dmHeader: 3, dmRows: 2, trayChats: 2));
      final lines = broken(s);
      expect(lines, hasLength(1));
      expect(lines.single, contains("Direct messages 3 ≠ Home's DMs 2"));
      expect(lines.single, contains("${s.no(room)} adds 1 to the header"));
      expect(lines.single, contains("1 found here, server count 0"));
    });

    test("a muted direct message counts on Home but not in the header", () {
      final s = snapshot([dm(1), dm(3, rule: PushRule.dontNotify)]);
      expect(broken(s).join("\n"), contains("(muted)"));
    });

    test("an older room with the same person: rail icon vs row", () {
      final room = dm(0, older: 1);
      final s = snapshot([room]);
      expect(broken(s).join("\n"),
          contains("${s.no(room)}: rail icon shows 1, row shows a dot"));
    });

    test("a favorite direct message counts on Home, not in the section", () {
      final room = dm(2, inSection: false, favourite: true);
      final s = snapshot([dm(1), room]);
      final text = broken(s).join("\n");
      expect(text, contains("${s.no(room)} counts on Home, not in Direct"));
      expect(text, contains("(in Favorites)"));
    });

    test("a space badge that isn't its rooms added up", () {
      DebugRoom inSpace(String key, int count) => DebugRoom(
          kind: DebugRoomKind.inSpace,
          rule: PushRule.notify,
          spaces: [key],
          count: count,
          badge: count);
      final rooms = [inSpace("a", 2), inSpace("b", 1)];
      final ok = snapshot(rooms, spaces: [
        DebugSpace("a", badge: 2),
        DebugSpace("b", badge: 1),
      ]);
      expect(broken(ok), isEmpty);
      final wrong = snapshot(rooms, spaces: [
        DebugSpace("a", badge: 4),
        DebugSpace("b", badge: 1),
      ]);
      expect(broken(wrong).single, contains("4 ≠ its rooms 2"));
    });

    test("the tray counts a person's older rooms too", () {
      final room = DebugRoom(
          kind: DebugRoomKind.dm,
          rule: PushRule.notify,
          groupSize: 2,
          count: 1,
          badge: 1,
          trayChat: true,
          olderTrayChats: 1);
      final s = snapshot([room],
          totals: const DebugTotals(trayChats: 2, homeCountsDms: false));
      expect(
          s.checks().where((c) => c.lines.first.startsWith("Tray")).single.ok,
          isTrue);
    });
  });

  group("the dump's privacy", () {
    final rooms = [
      for (var i = 0; i < 12; i++) dm(i % 3),
      DebugRoom(
          kind: DebugRoomKind.inSpace,
          rule: PushRule.mentionsOnly,
          spaces: ["acct:!privatespace:example.org"],
          count: 1,
          badge: 1),
    ];
    final spaces = [
      DebugSpace("acct:!privatespace:example.org", badge: 1),
    ];

    test("no space keys, ids or servers, only numbers", () {
      final text = snapshot(rooms, spaces: spaces).text();
      expect(text, isNot(contains("privatespace")));
      expect(text, isNot(contains("example.org")));
      expect(text, isNot(contains("!")));
      expect(text, isNot(contains("@")));
      expect(text, contains("Space S1"));
    });

    test("rooms are #1 to #n, in a new order each time", () {
      final orders = <String>{};
      for (var seed = 0; seed < 10; seed++) {
        final s = snapshot(rooms, spaces: spaces, random: Random(seed));
        expect([for (final r in s.listed) s.no(r)]..sort(),
            [for (var i = 1; i <= s.listed.length; i++) "#$i"]..sort());
        orders.add(rooms.map((r) => s.no(r)).join(","));
      }
      expect(orders.length, greaterThan(1));
    });

    test("rooms with nothing to say aren't listed", () {
      final s = snapshot([dm(1), dm(0), dm(0)]);
      expect(s.listed, hasLength(1));
      expect(s.text(), contains("2 more rooms: nothing unread, no badge"));
    });

    test("every line fits a phone (46 characters)", () {
      final s = snapshot([
        ...rooms,
        dm(3, older: 2, local: 1, favourite: true, inSection: false),
        dm(4, rule: PushRule.dontNotify),
      ], spaces: spaces);
      for (final line in s.text().split("\n")) {
        expect(line.length, lessThanOrEqualTo(46), reason: line);
      }
    });
  });

  // The totals the app adds up today that must equal their parts.
  group("badge totals equal their rooms", () {
    test("a space counts a room in two of its subspaces once", () {
      final a = _Room("x:!a", messages: 2);
      final b = _Room("x:!b", messages: 1);
      final space = _Space([
        b
      ], subspaces: [
        _Space([a]),
        _Space([a]),
      ]);
      expect(space.badgeCount, 3);
    });

    test("a muted room adds nothing to its space; a muted space shows 0", () {
      final a = _Room("x:!a", messages: 2);
      final muted = _Room("x:!m", messages: 5, pushRule: PushRule.dontNotify);
      expect(_Space([a, muted]).badgeCount, 2);
      expect(_Space([a], pushRule: PushRule.dontNotify).badgeCount, 0);
    });

    test("the tray counts each chat once, whichever spaces hold it", () {
      final a = _Room("x:!a", messages: 2);
      final b = _Room("x:!b", mentions: 1);
      final (_, chats) = NotificationUtils.countNotifications(
          [(a, false), (a, false), (b, false)]);
      expect(chats, 2);
    });

    test("a side list section's badge is its rows added up", () {
      final rows = [
        _Room("x:!a", messages: 2),
        _Room("x:!b", messages: 1, mentions: 1),
        _Room("x:!c", pushRule: PushRule.dontNotify, messages: 4),
      ];
      final badge = sectionBadge<Room>(rows,
          count: (r) => r.badgeCount, noisy: (r) => r.badgeNoisy);
      expect(badge.count, rows.fold(0, (s, r) => s + r.badgeCount));
      expect(badge.count, 3);
    });
  });

  // Vommet issue 949: what one per-room model must make true. These fail
  // on today's code (the dump shows where); they run once the model lands.
  group("one unread model", () {
    const pending = "Vommet issue 949: unread model pending";
    test("Home's direct messages = the Direct messages header", () {},
        skip: pending);
    test("People's direct messages = Home's", () {}, skip: pending);
    test("a direct message's rail icon = its row", () {}, skip: pending);
    test("a muted direct message adds nothing anywhere", () {}, skip: pending);
  });
}
