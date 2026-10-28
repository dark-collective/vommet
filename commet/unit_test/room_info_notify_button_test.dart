import 'package:commet/client/client.dart';
import 'package:commet/ui/pages/room_info/room_info_notifications.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiamat/config/style/theme_dark.dart';

// Vommet (New room info page): the notification quick action shows the
// current level, and a tap opens the levels instead of muting.
Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
      MaterialApp(
        theme: ThemeDark.theme,
        home: Scaffold(body: Row(children: [child])),
      ),
    );

void main() {
  testWidgets("the label is the current level, Notifications underneath", (
    tester,
  ) async {
    await _pump(
      tester,
      NotificationQuickAction(pushRule: PushRule.mentionsOnly, onTap: () {}),
    );
    expect(find.text("Mentions"), findsOneWidget);
    expect(find.text("Notifications"), findsOneWidget);
    expect(
      find.byKey(const ValueKey("push-rule-icon-mentions")),
      findsOneWidget,
    );
    expect(find.text("Mute"), findsNothing);
    expect(find.text("Unmute"), findsNothing);

    await _pump(
      tester,
      NotificationQuickAction(pushRule: PushRule.dontNotify, onTap: () {}),
    );
    expect(find.text("Muted"), findsOneWidget);
    expect(find.byIcon(Icons.notifications_off_outlined), findsOneWidget);

    await _pump(
      tester,
      NotificationQuickAction(
        pushRule: PushRule.notify,
        followsDefault: true,
        onTap: () {},
      ),
    );
    expect(find.text("All messages"), findsOneWidget);
    expect(find.text("Notifications (default)"), findsOneWidget);
    expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);
  });

  testWidgets("tap and long-press both open, nothing changes by itself", (
    tester,
  ) async {
    var opened = 0;
    await _pump(
      tester,
      NotificationQuickAction(pushRule: PushRule.notify, onTap: () => opened++),
    );
    await tester.tap(find.text("All messages"));
    await tester.longPress(find.text("All messages"));
    expect(opened, 2);
  });

  Future<List<NotificationPick>> pumpList(
    WidgetTester tester, {
    required PushRule pushRule,
    PushRule? defaultLevel,
    bool followsDefault = false,
  }) async {
    final picks = <NotificationPick>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeDark.theme,
        home: Scaffold(
          body: NotificationLevelList(
            pushRule: pushRule,
            defaultLevel: defaultLevel,
            followsDefault: followsDefault,
            onPicked: picks.add,
          ),
        ),
      ),
    );
    return picks;
  }

  bool selected(WidgetTester tester, String key) => tester
      .widget<ListTile>(find.byKey(ValueKey("notification-choice-$key")))
      .selected;

  testWidgets("four choices; Use default selected when following it", (
    tester,
  ) async {
    final picks = await pumpList(
      tester,
      pushRule: PushRule.mentionsOnly,
      defaultLevel: PushRule.mentionsOnly,
      followsDefault: true,
    );
    expect(find.text("Use default (Mentions & keywords)"), findsOneWidget);
    expect(find.text("All messages"), findsOneWidget);
    expect(find.text("Mentions & keywords"), findsOneWidget);
    expect(find.text("Muted"), findsOneWidget);
    expect(selected(tester, "default"), isTrue);
    expect(selected(tester, "mentionsOnly"), isFalse);

    await tester.tap(find.text("Use default (Mentions & keywords)"));
    await tester.tap(find.text("Muted"));
    expect(picks.map((p) => p.rule), [null, PushRule.dontNotify]);
  });

  testWidgets("an own level is selected, not Use default", (tester) async {
    await pumpList(
      tester,
      pushRule: PushRule.mentionsOnly,
      defaultLevel: PushRule.notify,
    );
    expect(selected(tester, "default"), isFalse);
    expect(selected(tester, "mentionsOnly"), isTrue);
  });

  testWidgets("no default level: only the three levels", (tester) async {
    await pumpList(tester, pushRule: PushRule.notify, followsDefault: true);
    expect(find.textContaining("Use default"), findsNothing);
    expect(selected(tester, "notify"), isTrue);
  });
}
