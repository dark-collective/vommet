import 'package:commet/client/client.dart';
import 'package:commet/config/layout_style.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/molecules/message_input.dart';
import 'package:commet/utils/autofill_utils.dart';
import 'package:commet/utils/emoji/unicode_emoji.dart';
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
          AutofillSearchResult("@room", "@room"),
        ]
      : text.startsWith(":")
          ? [
              AutofillSearchResultEmoticon(
                  ":fire:", "🔥", UnicodeEmoticon("🔥", shortcode: "fire")),
            ]
          : [];

  Future<void> pump(WidgetTester tester, {bool expanded = false}) async {
    tester.view.physicalSize = const Size(412, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              if (!expanded)
                const Expanded(child: ColoredBox(color: Colors.teal)),
              Flexible(
                flex: expanded ? 1 : 0,
                child: MessageInput(
                  client: FakeClient(),
                  expanded: expanded ? ValueNotifier(true) : null,
                  availibleEmoticons: const [],
                  processAutofill: autofill,
                  onSendMessage: (message, {overrideClient}) =>
                      MessageInputSendResult.success,
                ),
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

  // The box's own bottom padding; nothing else sits under it on phones.
  const kPhoneGap = 0.0;

  double gapUnderBox(WidgetTester tester) =>
      700 - tester.getRect(find.byKey(boxKey)).bottom;

  testWidgets("phone: no reserved row under the box", (tester) async {
    await preferences.layoutOverride.set("mobile");
    await pump(tester);
    expect(gapUnderBox(tester), moreOrLessEquals(kPhoneGap, epsilon: 0.5));
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

    // Members show their Matrix ID on the right; @room shows none.
    final ids = find.descendant(
        of: card,
        matching: find.byKey(const ValueKey("composer-autofill-secondary")));
    expect(ids, findsNWidgets(2));
    final aliceId = find.descendant(of: card, matching: find.text("@alice:x"));
    expect(aliceId, findsOneWidget);
    expect(tester.getTopLeft(aliceId).dx,
        greaterThan(tester.getTopRight(alice).dx));
    expect(find.descendant(of: card, matching: find.text("@room")),
        findsOneWidget);

    await tester.tap(albert);
    await tester.pump();
    await tester.pump();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, contains("@albert:x"));
    expect(card, findsNothing);
  });

  testWidgets("phone: emoji rows show no secondary text", (tester) async {
    await preferences.layoutOverride.set("mobile");
    await pump(tester);
    await type(tester, "hi :fi");
    expect(card, findsOneWidget);
    expect(find.descendant(of: card, matching: find.text(":fire:")),
        findsOneWidget);
    expect(find.byKey(const ValueKey("composer-autofill-secondary")),
        findsNothing);
  });

  testWidgets("phone, Telegram style: autocomplete floats above the box",
      (tester) async {
    await preferences.layoutOverride.set("mobile");
    await pickLayoutStyle(LayoutStyle.telegram);
    addTearDown(() => pickLayoutStyle(LayoutStyle.discord));
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

  testWidgets("phone, expanded composer: the card stays on-screen",
      (tester) async {
    await preferences.layoutOverride.set("mobile");
    await pump(tester, expanded: true);
    await type(tester, "hi @al");
    final box = tester.getRect(find.byKey(boxKey));
    expect(box.height, greaterThan(300));
    expect(card, findsOneWidget);
    final rect = tester.getRect(card);
    const screen = Rect.fromLTWH(0, 0, 412, 700);
    expect(screen.contains(rect.topLeft), isTrue);
    expect(screen.contains(rect.bottomRight - const Offset(0.1, 0.1)), isTrue);
    expect(rect.top, greaterThanOrEqualTo(box.top - 20));
  });

  testWidgets("desktop: the row under the box stays", (tester) async {
    await preferences.layoutOverride.set("desktop");
    await pump(tester);
    expect(gapUnderBox(tester), greaterThanOrEqualTo(30));
    expect(card, findsNothing);
  });
}
