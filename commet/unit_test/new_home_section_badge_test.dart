import 'package:commet/ui/atoms/notification_badge.dart';
import 'package:commet/ui/organisms/new_home/new_home_column.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Vommet issue 627: a New Home side list section has a badge, like a space.
// Vommet issue 719: it adds up its rooms' badge counts, red when one of them
// is noisy and grey when all are silent; rooms that are only unread add
// nothing.

typedef _Room = ({int count, bool noisy});

({int count, bool noisy}) badgeOf(List<_Room> rooms) =>
    sectionBadge(rooms, count: (r) => r.count, noisy: (r) => r.noisy);

void main() {
  test("rooms that are only unread get no badge", () {
    final badge = badgeOf([
      (count: 0, noisy: false),
      (count: 0, noisy: false),
    ]);
    expect(badge.count, 0);
    expect(badge.noisy, isFalse);
  });

  test("silent rooms add up to a grey count", () {
    final badge = badgeOf([
      (count: 3, noisy: false),
      (count: 12, noisy: false),
      (count: 0, noisy: false),
    ]);
    expect(badge.count, 15);
    expect(badge.noisy, isFalse);
  });

  test("one noisy room makes the whole count red", () {
    final badge = badgeOf([
      (count: 4, noisy: true),
      (count: 2, noisy: false),
    ]);
    expect(badge.count, 6);
    expect(badge.noisy, isTrue);
  });

  test("a noisy room with nothing counted doesn't color the badge", () {
    final badge = badgeOf([
      (count: 0, noisy: true),
      (count: 2, noisy: false),
    ]);
    expect(badge.count, 2);
    expect(badge.noisy, isFalse);
  });

  Future<void> pumpHeader(WidgetTester tester,
          {int count = 0, bool noisy = false}) =>
      tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SideListSectionHeader(
              title: "Favourites",
              collapsed: false,
              count: count,
              noisy: noisy),
        ),
      ));

  NotificationBadge badge(WidgetTester tester) =>
      tester.widget<NotificationBadge>(find.byType(NotificationBadge));

  testWidgets("the header shows a red count, a grey count or nothing",
      (tester) async {
    await pumpHeader(tester, count: 2, noisy: true);
    expect(badge(tester).noisy, isTrue);

    await pumpHeader(tester, count: 5);
    expect(badge(tester).count, 5);
    expect(badge(tester).noisy, isFalse);

    await pumpHeader(tester);
    expect(find.byType(NotificationBadge), findsNothing);
  });
}
