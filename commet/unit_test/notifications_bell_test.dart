import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/config/preferences/preference.dart';
import 'package:commet/ui/organisms/new_home/new_home_main.dart';
import 'package:commet/ui/organisms/new_home/new_home_notifications_model.dart';
import 'package:commet/ui/organisms/new_home/new_home_tabs.dart';
import 'package:commet/ui/organisms/new_home/notifications_bell.dart';
import 'package:commet/ui/organisms/new_home/notifications_feed.dart';
import 'package:commet/utils/notifying_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Vommet issues 841 and 873: the notifications bell and its pop-over, on the
// Notifications card's shared feed.

class _ClientManager extends Fake implements ClientManager {
  @override
  NotifyingList<Client> clients = NotifyingList.empty(growable: true);
  @override
  StreamController<void> onSync = StreamController.broadcast();
}

NotificationEntry _e(String event,
        {String room = "!r", bool read = false, int minutesAgo = 5}) =>
    NotificationEntry(
        clientId: "c",
        roomId: room,
        eventId: event,
        senderId: "@a:x",
        time: DateTime.now().subtract(Duration(minutes: minutesAgo)),
        read: read);

void main() {
  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    Preference.preferences = await SharedPreferences.getInstance();
  });

  test("one feed per account manager and filter", () {
    final a = _ClientManager();
    final b = _ClientManager();
    expect(
        identical(NotificationsFeed.of(a, null), NotificationsFeed.of(a, null)),
        isTrue);
    expect(
        identical(NotificationsFeed.of(a, null), NotificationsFeed.of(b, null)),
        isFalse);
  });

  test("the bell counts the list's unread items once each", () {
    final feed = NotificationsFeed.of(_ClientManager(), null);
    expect(feed.unreadCount, 0);
    feed.entries = [
      _e("\$1"),
      _e("\$1", read: true),
      _e("\$2", room: "!s"),
      _e("\$3", read: true),
      _e("\$old", minutesAgo: 60 * 24 * 8)
    ];
    expect(feed.unreadCount, 2);
    expect(feed.arranged().length, 3);
  });

  testWidgets("the pop-over says when it's empty and offers Hide read",
      (tester) async {
    final feed = NotificationsFeed.of(_ClientManager(), null);
    var closed = false;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body:
                NotificationsPanel(feed: feed, onClose: () => closed = true))));
    await tester.pumpAndSettle();
    expect(find.text("Notifications"), findsOneWidget);
    expect(find.text("No notifications in the last 7 days."), findsOneWidget);
    // Nothing unread: no "Mark all read".
    expect(find.text("Mark all read"), findsNothing);

    await tester.tap(find.byKey(const ValueKey("NotificationsPanelSettings")));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Hide read"));
    await tester.pumpAndSettle();
    expect(find.text("You're all caught up."), findsOneWidget);
    expect(notificationsHideRead.value, isTrue);
    expect(closed, isFalse);
  });

  for (final phone in [false, true]) {
    testWidgets("the Home header has the bell on phones only (phone: $phone)",
        (tester) async {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SizedBox(
                  width: phone ? 380 : 1200,
                  child: NewHomeHeader(
                      tab: HomeTabs.defaultTab(HomeTabs.overview)!,
                      phone: phone)))));
      expect(find.byKey(const ValueKey("NotificationsBell")),
          phone ? findsOneWidget : findsNothing);
    });
  }
}
