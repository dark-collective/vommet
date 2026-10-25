// Vommet issue 654: the tray and taskbar count chats with notifications,
// each once, and badges count past 9.
import 'package:commet/client/room.dart';
import 'package:commet/ui/atoms/notification_badge.dart';
import 'package:commet/ui/organisms/new_home/new_home_people_store.dart';
import 'package:commet/utils/notification_utils.dart';
import 'package:commet/utils/notifying_list.dart';
import 'package:commet/utils/notifying_list_filter.dart';
import 'package:commet/utils/notifying_list_mapped.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Room extends Fake implements Room {
  _Room(this.localId, {this.messages = 0, this.mentions = 0});

  @override
  final String localId;
  final int messages;
  final int mentions;

  @override
  int get notificationCount => messages;
  @override
  int get displayNotificationCount => messages;
  @override
  int get displayHighlightedNotificationCount => mentions;
}

void main() {
  group("countNotifications", () {
    test("counts chats, not messages", () {
      final counts = NotificationUtils.countNotifications([
        (_Room("a:!busy", messages: 30), false),
        (_Room("a:!quiet", messages: 1), false),
        (_Room("a:!read"), false),
      ]);
      expect(counts.$2, 2);
    });

    test("a room in several spaces, or also a DM, counts once", () {
      final room = _Room("a:!shared", messages: 4, mentions: 1);
      final dm = _Room("a:!dm", messages: 2);
      final counts = NotificationUtils.countNotifications(
          [(room, false), (room, false), (dm, true), (dm, true)]);
      expect(counts, (1 + 2, 2));
    });

    test("every DM message is red; in rooms only mentions are", () {
      final counts = NotificationUtils.countNotifications([
        (_Room("a:!dm", messages: 3), true),
        (_Room("a:!room", messages: 5, mentions: 1), false),
      ]);
      expect(counts.$1, 4);
    });

    test("the same room in two accounts is two chats", () {
      final counts = NotificationUtils.countNotifications([
        (_Room("a:!room", messages: 1), false),
        (_Room("b:!room", messages: 1), false),
      ]);
      expect(counts.$2, 2);
    });

    test("a mention alone counts the chat", () {
      final counts = NotificationUtils.countNotifications(
          [(_Room("a:!muted", mentions: 1), false)]);
      expect(counts, (1, 1));
    });
  });

  test("People counts unread messages across DMs", () {
    expect(
        NewHomeInvites.unreadDirectMessages(
            [_Room("a:!x", messages: 2), _Room("a:!y", messages: 9)]),
        11);
    expect(NewHomeInvites.unreadDirectMessages(const []), 0);
  });

  test("People counts DMs from the real (filtered, per-account) lists", () {
    // The DM list is a NotifyingListMapped over NotifyingListFilters, whose
    // fold used to throw UnimplementedError, so the badge never updated.
    final rooms = NotifyingList<Room>.from(
        [_Room("a:!x", messages: 2), _Room("a:!y"), _Room("a:!z", messages: 9)],
        growable: true);
    final unread =
        NotifyingListFilter(rooms, where: (r) => r.notificationCount > 0);
    final accounts =
        NotifyingList<INotifyingList<Room>>.from([unread], growable: true);
    final dms = NotifyingListMapped<Room, INotifyingList<Room>>(
        baseList: accounts, map: (list) => list);
    expect(NewHomeInvites.unreadDirectMessages(unread), 11);
    expect(NewHomeInvites.unreadDirectMessages(dms), 11);
  });

  test("badges count to 99, then say 99+", () {
    expect(notificationBadgeText(1), "1");
    expect(notificationBadgeText(15), "15");
    expect(notificationBadgeText(99), "99");
    expect(notificationBadgeText(100), "99+");
  });

  testWidgets("a two-digit badge widens into a pill", (tester) async {
    Future<Size> sizeOf(int count) async {
      await tester.pumpWidget(MaterialApp(
          home: Center(child: NotificationBadge(count, key: ValueKey(count)))));
      return tester.getSize(find.byType(NotificationBadge));
    }

    final one = await sizeOf(3);
    final two = await sizeOf(15);
    expect(one, const Size(16, 16));
    expect(two.height, 16);
    expect(two.width, greaterThan(16));
    expect(find.text("15"), findsOneWidget);
  });
}
