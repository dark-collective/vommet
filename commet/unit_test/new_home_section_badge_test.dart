import 'package:commet/ui/atoms/notification_badge.dart';
import 'package:commet/ui/organisms/new_home/new_home_column.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Vommet issue 627: a New Home side list section's badge counts mentions and
// keyword hits only; a noisy notification without them is a red dot; rooms
// that are only unread add nothing.

typedef _Room = ({int mentions, int notifications, bool dm});

({int mentions, bool noisy}) badgeOf(List<_Room> rooms) => sectionBadge(rooms,
    mentions: (r) => r.mentions,
    notifications: (r) => r.notifications,
    isDirectMessage: (r) => r.dm);

void main() {
  test("unread group rooms without mentions get no badge", () {
    final badge = badgeOf([
      (mentions: 0, notifications: 3, dm: false),
      (mentions: 0, notifications: 12, dm: false),
    ]);
    expect(badge.mentions, 0);
    expect(badge.noisy, isFalse);
  });

  test("mentions and keyword hits are counted", () {
    final badge = badgeOf([
      (mentions: 2, notifications: 5, dm: false),
      (mentions: 1, notifications: 1, dm: false),
      (mentions: 0, notifications: 9, dm: false),
    ]);
    expect(badge.mentions, 3);
    expect(badge.noisy, isTrue);
  });

  test("a direct message's notification is a dot without a number", () {
    final badge = badgeOf([
      (mentions: 0, notifications: 4, dm: true),
      (mentions: 0, notifications: 2, dm: false),
    ]);
    expect(badge.mentions, 0);
    expect(badge.noisy, isTrue);
  });

  test("read rooms clear the badge", () {
    final badge = badgeOf([(mentions: 0, notifications: 0, dm: true)]);
    expect(badge.mentions, 0);
    expect(badge.noisy, isFalse);
  });

  Future<void> pumpHeader(WidgetTester tester,
          {int mentions = 0, bool noisy = false}) =>
      tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SideListSectionHeader(
              title: "Favourites",
              collapsed: false,
              mentions: mentions,
              noisy: noisy),
        ),
      ));

  testWidgets("the header shows a count, a dot or nothing", (tester) async {
    await pumpHeader(tester, mentions: 2, noisy: true);
    expect(find.byType(NotificationBadge), findsOneWidget);
    expect(find.byKey(const ValueKey("NewHomeSectionDot-Favourites")),
        findsNothing);

    await pumpHeader(tester, noisy: true);
    expect(find.byType(NotificationBadge), findsNothing);
    expect(find.byKey(const ValueKey("NewHomeSectionDot-Favourites")),
        findsOneWidget);

    await pumpHeader(tester);
    expect(find.byType(NotificationBadge), findsNothing);
    expect(find.byKey(const ValueKey("NewHomeSectionDot-Favourites")),
        findsNothing);
  });
}
