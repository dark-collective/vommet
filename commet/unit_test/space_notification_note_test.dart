import 'package:commet/client/client.dart';
import 'package:commet/ui/pages/settings/categories/room/general/room_general_settings_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiamat/config/style/theme_dark.dart';

Future<void> _pump(WidgetTester tester,
    {String? note,
    PushRule pushRule = PushRule.dontNotify,
    bool followsDefault = false}) {
  return tester.pumpWidget(MaterialApp(
    theme: ThemeDark.theme,
    home: Scaffold(
      body: SingleChildScrollView(
        child: RoomGeneralSettingsView(
            pushRule: pushRule,
            onPushRuleChanged: (_) {},
            note: note,
            followsDefault: followsDefault),
      ),
    ),
  ));
}

void main() {
  // Vommet issue 315: a space's notification choice doesn't change its rooms,
  // so the space settings page says what it does affect.
  testWidgets("shows the note under the choices", (tester) async {
    const note = "Mute hides this space's unread dot.";
    await _pump(tester, note: note);

    expect(find.text(note), findsOneWidget);
    expect(tester.getTopLeft(find.text(note)).dy,
        greaterThan(tester.getTopLeft(find.text("Mute")).dy));
  });

  testWidgets("rooms show no note", (tester) async {
    await _pump(tester);

    expect(find.text("Mute"), findsOneWidget);
    expect(find.textContaining("unread dot"), findsNothing);
  });

  // A room without a rule of its own follows the account's defaults; its
  // choice says so.
  testWidgets("a room on the default says Default (…)", (tester) async {
    await _pump(tester, pushRule: PushRule.mentionsOnly, followsDefault: true);

    expect(find.text("Default (Mentions & Keywords)"), findsOneWidget);
    expect(find.text("All Messages"), findsOneWidget);
    expect(find.text("Mute"), findsOneWidget);
  });

  testWidgets("a room's own setting has the plain name", (tester) async {
    await _pump(tester, pushRule: PushRule.mentionsOnly);

    expect(find.text("Mentions & Keywords"), findsOneWidget);
    expect(find.textContaining("Default"), findsNothing);
  });
}
