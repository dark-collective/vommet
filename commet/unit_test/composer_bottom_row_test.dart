import 'package:commet/client/client.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/molecules/message_input.dart';
import 'package:commet/utils/autofill_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeClient implements Client {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

// Vommet: on phones there's no reserved row under the box; autocomplete
// floats above it as a vertical card. Desktop keeps the row.
void main() {
  setUp(() async {
    // unit_test/ isn't a recognised test directory for the analyzer.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });

  tearDown(() => preferences.layoutOverride.set(null));

  const boxKey = ValueKey("composer-input");
  final card = find.byKey(const ValueKey("composer-autofill-card"));

  List<AutofillSearchResult> autofill(String text) => text.startsWith("@")
      ? [
          AutofillSearchResultAvatar("Alice", "@alice:x", null, Colors.red),
          AutofillSearchResultAvatar("Albert", "@albert:x", null, Colors.blue),
        ]
      : [];

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(412, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              const Expanded(child: ColoredBox(color: Colors.teal)),
              MessageInput(
                client: FakeClient(),
                availibleEmoticons: const [],
                processAutofill: autofill,
                onSendMessage: (message, {overrideClient}) =>
                    MessageInputSendResult.success,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pump();
    await tester.pump();
  }

  double gapUnderBox(WidgetTester tester) =>
      700 - tester.getRect(find.byKey(boxKey)).bottom;

  testWidgets("phone: no reserved row under the box", (tester) async {
    await preferences.layoutOverride.set("mobile");
    await pump(tester);
    expect(gapUnderBox(tester), lessThan(30));
  });

  testWidgets("phone: autocomplete floats above the box", (tester) async {
    await preferences.layoutOverride.set("mobile");
    await pump(tester);
    await type(tester, "hi");
    final before = tester.getRect(find.byKey(boxKey));
    await type(tester, "hi @al");
    expect(tester.getRect(find.byKey(boxKey)), before);
    expect(card, findsOneWidget);
    expect(tester.getRect(card).bottom, lessThanOrEqualTo(before.top));
    final alice = find.descendant(of: card, matching: find.text("Alice"));
    final albert = find.descendant(of: card, matching: find.text("Albert"));
    expect(tester.getTopLeft(alice).dy, lessThan(tester.getTopLeft(albert).dy));

    await tester.tap(albert);
    await tester.pump();
    await tester.pump();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, contains("@albert:x"));
    expect(card, findsNothing);
  });

  testWidgets("desktop: the row under the box stays", (tester) async {
    await preferences.layoutOverride.set("desktop");
    await pump(tester);
    expect(gapUnderBox(tester), greaterThanOrEqualTo(30));
    expect(card, findsNothing);
  });
}
