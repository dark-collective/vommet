import 'package:commet/ui/molecules/timeline_events/message_text_selection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget app() => MaterialApp(
        home: Scaffold(
          body: Column(children: [
            const MessageTextSelectionScope(
                eventId: r"$one", child: Text("The address is 42 Willow Lane")),
            const MessageTextSelectionScope(
                eventId: r"$two", child: Text("Thanks!")),
            const SizedBox(height: 200, width: 200, key: Key("outside")),
          ]),
        ),
      );

  tearDown(() => MessageTextSelection.active.value = null);

  testWidgets("only the chosen message becomes selectable", (tester) async {
    await tester.pumpWidget(app());
    expect(find.byType(SelectableRegion), findsNothing);

    MessageTextSelection.start(r"$one");
    await tester.pumpAndSettle();

    expect(find.byType(SelectableRegion), findsOneWidget);
    expect(
        find.ancestor(
            of: find.text("The address is 42 Willow Lane"),
            matching: find.byType(SelectableRegion)),
        findsOneWidget);
  });

  testWidgets("tapping outside the message ends selection", (tester) async {
    await tester.pumpWidget(app());
    MessageTextSelection.start(r"$one");
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key("outside")));
    await tester.pumpAndSettle();

    expect(MessageTextSelection.active.value, isNull);
    expect(find.byType(SelectableRegion), findsNothing);
  });

  testWidgets("ending another message's selection is ignored", (tester) async {
    await tester.pumpWidget(app());
    MessageTextSelection.start(r"$one");
    await tester.pumpAndSettle();

    MessageTextSelection.end(r"$two");
    await tester.pumpAndSettle();

    expect(MessageTextSelection.active.value, r"$one");
    expect(find.byType(SelectableRegion), findsOneWidget);
  });

  testWidgets("closing a preview of the same message keeps its selection",
      (tester) async {
    var showPreview = ValueNotifier(true);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          const MessageTextSelectionScope(
              eventId: r"$one", child: Text("The address is 42 Willow Lane")),
          ValueListenableBuilder(
            valueListenable: showPreview,
            builder: (context, show, _) => show
                ? const MessageTextSelectionScope(
                    eventId: r"$one", child: Text("Preview"))
                : const SizedBox(),
          ),
        ]),
      ),
    ));

    MessageTextSelection.start(r"$one");
    showPreview.value = false;
    await tester.pumpAndSettle();

    expect(MessageTextSelection.active.value, r"$one");
    expect(
        find.ancestor(
            of: find.text("The address is 42 Willow Lane"),
            matching: find.byType(SelectableRegion)),
        findsOneWidget);
  });
}
