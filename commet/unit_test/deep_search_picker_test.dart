import 'package:commet/ui/organisms/new_home/deep_search/deep_search_picker.dart';
import 'package:commet/ui/organisms/new_home/deep_search/deep_search_query.dart';
import 'package:commet/ui/organisms/new_home/deep_search/deep_search_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Vommet (Deep Search follow-ups): the From ▾ chip opens the same picker
  // the typed from: token opens, in a popover; a pick adds the token as
  // typing would.
  const mira = DeepSearchToken<String>.from("@mira:example.org", "Mira");
  final people = [
    const DeepSearchPickerEntry<String>(
        token: mira, title: "Mira", subtitle: "@mira:example.org"),
    const DeepSearchPickerEntry<String>(
        token: DeepSearchToken<String>.from("@ola:example.org", "Ola"),
        title: "Ola",
        subtitle: "@ola:example.org"),
  ];
  List<DeepSearchPickerEntry<String>> source(String value) {
    final v = value.trim().toLowerCase();
    if (v.isEmpty) return people;
    return [
      for (final p in people)
        if (p.title.toLowerCase().contains(v)) p
    ];
  }

  Future<void> pumpChip(WidgetTester tester) async {
    var query = const DeepSearchQuery<String>();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => Column(children: [
            DeepSearchPickerChip<String>(DeepSearchStrings.chipFrom,
                pickerKey: "from",
                entries: source,
                selected: false,
                onPicked: (t) => setState(() => query = query.withToken(t))),
            for (final t in query.tokens) Text(t.label),
          ]),
        ),
      ),
    ));
  }

  testWidgets("the From chip's popover picks a sender", (tester) async {
    await pumpChip(tester);
    expect(find.text("From: Mira"), findsNothing);

    await tester.tap(find.text("From"));
    await tester.pumpAndSettle();
    expect(find.text(DeepSearchStrings.pickerFromHint), findsOneWidget);
    expect(find.text("Mira"), findsOneWidget);
    expect(find.text("Ola"), findsOneWidget);

    await tester.tap(find.text("Mira"));
    await tester.pumpAndSettle();
    expect(find.text(DeepSearchStrings.pickerFromHint), findsNothing);
    expect(find.text("From: Mira"), findsOneWidget);
  });

  testWidgets("typing in the popover narrows it; Enter picks the first",
      (tester) async {
    await pumpChip(tester);
    await tester.tap(find.text("From"));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), "ol");
    await tester.pump();
    expect(find.text("Mira"), findsNothing);
    expect(find.text("Ola"), findsOneWidget);

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text("From: Ola"), findsOneWidget);
  });

  testWidgets("no match shows No matches; tapping outside closes",
      (tester) async {
    await pumpChip(tester);
    await tester.tap(find.text("From"));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), "zz");
    await tester.pump();
    expect(find.text(DeepSearchStrings.pickerNoMatches), findsOneWidget);

    await tester.tapAt(const Offset(780, 580));
    await tester.pumpAndSettle();
    expect(find.text(DeepSearchStrings.pickerNoMatches), findsNothing);
    expect(find.textContaining("From: "), findsNothing);
  });
}
