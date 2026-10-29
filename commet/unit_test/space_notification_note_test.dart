import 'package:commet/client/client.dart';
import 'package:commet/ui/pages/settings/categories/room/general/room_general_settings_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiamat/config/style/theme_dark.dart';

Future<void> _pump(WidgetTester tester,
    {String? note,
    PushRule pushRule = PushRule.dontNotify,
    PushRule? defaultLevel,
    bool followsDefault = false,
    void Function(PushRule?)? onChanged}) {
  return tester.pumpWidget(MaterialApp(
    theme: ThemeDark.theme,
    home: Scaffold(
      body: SingleChildScrollView(
        child: RoomGeneralSettingsView(
            pushRule: pushRule,
            onPushRuleChanged: onChanged ?? (_) {},
            note: note,
            defaultLevel: defaultLevel,
            followsDefault: followsDefault),
      ),
    ),
  ));
}

/// The value of the selected notification choice.
PushRule? _selected(WidgetTester tester) => tester
    .widget<RadioListTile<PushRule?>>(
        find.byType(RadioListTile<PushRule?>).first)
    .groupValue;

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

  // A room without a rule of its own follows the account's defaults:
  // "Use default (…)" is selected, the levels keep their plain names.
  testWidgets("a room on the default selects Use default (…)", (tester) async {
    await _pump(tester,
        pushRule: PushRule.mentionsOnly,
        defaultLevel: PushRule.mentionsOnly,
        followsDefault: true);

    expect(find.text("Use default (Mentions & Keywords)"), findsOneWidget);
    expect(find.text("Mentions & Keywords"), findsOneWidget);
    expect(find.text("All Messages"), findsOneWidget);
    expect(find.text("Mute"), findsOneWidget);
    expect(_selected(tester), null);
    // The first choice, like the page's "Use global preference" rows.
    expect(tester.getTopLeft(find.text("Use default (Mentions & Keywords)")).dy,
        lessThan(tester.getTopLeft(find.text("All Messages")).dy));
  });

  testWidgets("a room's own setting is selected with its plain name",
      (tester) async {
    await _pump(tester,
        pushRule: PushRule.mentionsOnly, defaultLevel: PushRule.mentionsOnly);

    expect(_selected(tester), PushRule.mentionsOnly);
    expect(find.text("Use default (Mentions & Keywords)"), findsOneWidget);
    expect(find.textContaining("Default ("), findsNothing);
  });

  testWidgets("choosing Use default reports null, a level reports it",
      (tester) async {
    final chosen = <PushRule?>[];
    await _pump(tester,
        pushRule: PushRule.dontNotify,
        defaultLevel: PushRule.notify,
        onChanged: chosen.add);

    await tester.tap(find.text("Use default (All Messages)"));
    await tester.tap(find.text("All Messages"));
    expect(chosen, [null, PushRule.notify]);
  });

  testWidgets("spaces have no Use default choice", (tester) async {
    await _pump(tester, pushRule: PushRule.notify, followsDefault: true);

    expect(find.textContaining("Use default"), findsNothing);
    expect(_selected(tester), PushRule.notify);
  });
}
