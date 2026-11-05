// Vommet issue 252: the forward picker can filter by space, open subspaces,
// and shows where each room sits so same-named rooms can be told apart.

import 'package:commet/ui/organisms/forward_message/forward_picker_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<String> events;

  Future<void> pump(WidgetTester tester,
      {String selected = "all",
      List<String> breadcrumb = const [],
      List<ForwardPickerRow>? rows,
      String? actionLabel,
      String? actionHint}) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 500,
          height: 500,
          child: ForwardPickerView(
            searchHint: "Search",
            emptyText: "No rooms found",
            chips: const [
              ForwardPickerChip(id: "all", name: "All", icon: Icons.add),
              ForwardPickerChip(id: "dms", name: "DMs", icon: Icons.person),
              ForwardPickerChip(id: "games", name: "Games"),
              ForwardPickerChip(id: "work", name: "Work"),
            ],
            selectedChip: selected,
            onChipSelected: (id) => events.add("chip:$id"),
            breadcrumb: breadcrumb,
            onBreadcrumbSelected: (i) => events.add("crumb:$i"),
            actionLabel: actionLabel,
            onAction: () => events.add("action"),
            actionHint: actionHint,
            clearLabel: "Clear",
            onClear: () => events.add("clear"),
            rows: rows ??
                [
                  ForwardPickerRow(
                      title: "general",
                      subtitle: "Games",
                      onTap: () => events.add("room:games-general")),
                  ForwardPickerRow(
                      title: "general",
                      subtitle: "Work",
                      onTap: () => events.add("room:work-general")),
                ],
          ),
        ),
      ),
    ));
  }

  setUp(() => events = []);

  testWidgets("same-named rooms show where they are", (tester) async {
    await pump(tester);
    expect(find.text("general"), findsNWidgets(2));
    expect(find.text("Games"), findsWidgets);
    expect(find.text("Work"), findsWidgets);

    await tester.tap(find.text("general").last);
    expect(events, ["room:work-general"]);
  });

  testWidgets("space chips select a filter", (tester) async {
    await pump(tester);
    final chip = find.widgetWithText(ChoiceChip, "Games");
    expect(tester.widget<ChoiceChip>(chip).selected, isFalse);
    expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, "All"))
            .selected,
        isTrue);

    await tester.tap(chip);
    expect(events, ["chip:games"]);
  });

  testWidgets("subspaces open, and the breadcrumb goes back up",
      (tester) async {
    await pump(tester, selected: "games", breadcrumb: [
      "Games",
      "Minecraft"
    ], rows: [
      ForwardPickerRow(
          title: "Servers",
          isSpace: true,
          onTap: () => events.add("open:servers")),
      ForwardPickerRow(title: "general", onTap: () => events.add("room")),
    ]);

    expect(find.byIcon(Icons.chevron_right), findsWidgets);
    await tester.tap(find.text("Servers"));
    await tester.tap(find.widgetWithText(TextButton, "Games"));
    // The open subspace itself isn't a link.
    await tester.tap(find.widgetWithText(TextButton, "Minecraft"));
    expect(events, ["open:servers", "crumb:0"]);
  });

  testWidgets("no breadcrumb at the top of a space", (tester) async {
    await pump(tester, selected: "games", breadcrumb: ["Games"]);
    expect(find.byType(TextButton), findsNothing);
  });

  testWidgets("empty list shows the empty text", (tester) async {
    await pump(tester, rows: const []);
    expect(find.text("No rooms found"), findsOneWidget);
  });

  // Vommet issue 803: long-press ticks rooms; ticked rooms show a tickbox.
  testWidgets("long-press starts ticking, tickboxes show the ticks",
      (tester) async {
    await pump(tester, rows: [
      ForwardPickerRow(
          title: "general",
          onTap: () => events.add("tap"),
          onLongPress: () => events.add("long")),
    ]);
    expect(find.byType(Checkbox), findsNothing);
    await tester.longPress(find.text("general"));
    expect(events, ["long"]);

    await pump(tester, actionLabel: "Forward to 2 rooms", rows: [
      const ForwardPickerRow.header("Selected · 2"),
      ForwardPickerRow(
          title: "general", selected: true, onTap: () => events.add("a")),
      ForwardPickerRow(
          title: "random", selected: false, onTap: () => events.add("b")),
    ]);
    expect(find.text("Selected · 2"), findsOneWidget);
    final boxes = tester.widgetList<Checkbox>(find.byType(Checkbox));
    expect(boxes.map((b) => b.value), [true, false]);

    await tester.tap(find.byType(Checkbox).last);
    await tester.tap(find.text("Forward to 2 rooms"));
    expect(events, ["long", "b", "action"]);
  });

  testWidgets("no action button outside select mode", (tester) async {
    await pump(tester);
    expect(find.byIcon(Icons.send), findsNothing);
    expect(find.text("Clear"), findsNothing);
  });

  // Vommet issue 881: the hint and Clear sit over the forward button, and
  // the last-ticked room has an info icon with a tooltip.
  testWidgets("hint, Clear, and the info tooltip", (tester) async {
    await pump(tester,
        actionLabel: "Forward to 2 rooms",
        actionHint: "Tick more rooms, or forward now.",
        rows: [
          ForwardPickerRow(
              title: "general", selected: true, onTap: () => events.add("a")),
          ForwardPickerRow(
              title: "random",
              selected: true,
              info: "Opens random, your last pick.",
              onTap: () => events.add("b")),
        ]);
    expect(find.text("Tick more rooms, or forward now."), findsOneWidget);
    expect(find.byIcon(Icons.info_outline), findsOneWidget);

    // Tapping the icon shows the tooltip and doesn't untick the room.
    await tester.tap(find.byIcon(Icons.info_outline));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text("Opens random, your last pick."), findsOneWidget);
    await tester.pump(const Duration(seconds: 7));

    await tester.tap(find.text("Clear"));
    expect(events, ["clear"]);
  });
}
