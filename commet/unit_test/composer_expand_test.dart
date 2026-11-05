import 'package:commet/client/client.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/molecules/composer_expand.dart';
import 'package:commet/ui/molecules/message_input.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeClient implements Client {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

// Vommet composer round 6: on phones, a draft of 3+ lines shows ⤢, which
// makes the same box fill the chat; ⤡ or sending shrinks it back.
void main() {
  late List<String> sent;
  late ValueNotifier<bool> expanded;

  setUp(() async {
    // unit_test/ isn't a recognised test directory for the analyzer.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    sent = [];
    expanded = ValueNotifier(false);
  });

  tearDown(() => preferences.layoutOverride.set(null));

  const timelineKey = ValueKey("timeline");

  // Laid out like the chat: the timeline, then the composer.
  Future<void> pumpChat(WidgetTester tester) async {
    tester.view.physicalSize = const Size(412, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ValueListenableBuilder<bool>(
          valueListenable: expanded,
          builder: (context, value, _) => Column(children: [
            composerTimelineSlot(
                composerExpanded: value,
                child: const ColoredBox(key: timelineKey, color: Colors.teal)),
            composerSlot(
              expanded: value,
              child: MessageInput(
                client: FakeClient(),
                availibleEmoticons: const [],
                expanded: expanded,
                onSendMessage: (message, {overrideClient}) {
                  sent.add(message);
                  return MessageInputSendResult.success;
                },
              ),
            ),
          ]),
        ),
      ),
    ));
    await tester.pump();
  }

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pump();
    await tester.pump();
  }

  final expandButton = find.byKey(const ValueKey("composer-expand"));
  final collapseButton = find.byKey(const ValueKey("composer-collapse"));

  testWidgets("mobile: ⤢ shows from 3 lines", (tester) async {
    await preferences.layoutOverride.set("mobile");
    await pumpChat(tester);
    await type(tester, "one\ntwo");
    expect(expandButton, findsNothing);
    await type(tester, "one\ntwo\nthree");
    expect(expandButton, findsOneWidget);
    await type(tester, "one");
    expect(expandButton, findsNothing);
  });

  testWidgets("desktop: never ⤢", (tester) async {
    await preferences.layoutOverride.set("desktop");
    await pumpChat(tester);
    await type(tester, "one\ntwo\nthree\nfour");
    expect(expandButton, findsNothing);
  });

  testWidgets("mobile: ⤢ fills the chat, ⤡ shrinks it back", (tester) async {
    await preferences.layoutOverride.set("mobile");
    await pumpChat(tester);
    await type(tester, "one\ntwo\nthree");
    final field = tester.widget<TextField>(find.byType(TextField));
    field.focusNode!.requestFocus();
    await tester.pump();
    final small = tester.getRect(find.byKey(const ValueKey("composer-input")));

    await tester.tap(expandButton);
    await tester.pump();
    expect(expanded.value, isTrue);
    expect(collapseButton, findsOneWidget);
    final big = tester.getRect(find.byKey(const ValueKey("composer-input")));
    expect(big.height, greaterThan(500));
    expect(tester.getSize(find.byKey(timelineKey)).height,
        greaterThan(0)); // laid out at its old size, just not shown
    // The same field, still focused: the keyboard stays up.
    expect(tester.widget<TextField>(find.byType(TextField)).focusNode,
        same(field.focusNode));
    expect(field.focusNode!.hasFocus, isTrue);
    expect(find.text("one\ntwo\nthree"), findsOneWidget);
    // + bottom-left, Send bottom-right, inside the box.
    final plus = tester.getRect(find.byKey(const ValueKey("composer-attach")));
    final sendRect = tester.getRect(find.byIcon(Icons.send));
    expect(plus.bottom, closeTo(big.bottom, 12));
    expect(sendRect.bottom, closeTo(big.bottom, 12));
    expect(sendRect.right, greaterThan(big.center.dx));
    expect(plus.left, lessThan(big.center.dx));

    await tester.tap(collapseButton);
    await tester.pump();
    await tester.pump();
    expect(expanded.value, isFalse);
    expect(tester.getRect(find.byKey(const ValueKey("composer-input"))).height,
        closeTo(small.height, 1));
    expect(field.focusNode!.hasFocus, isTrue);
    expect(expandButton, findsOneWidget);
  });

  testWidgets("mobile: sending shrinks the box", (tester) async {
    await preferences.layoutOverride.set("mobile");
    await pumpChat(tester);
    await type(tester, "one\ntwo\nthree");
    await tester.tap(expandButton);
    await tester.pump();
    expect(expanded.value, isTrue);

    await tester.tap(find.byIcon(Icons.send));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    expect(sent, ["one\ntwo\nthree"]);
    expect(expanded.value, isFalse);
    expect(collapseButton, findsNothing);
    expect(expandButton, findsNothing);
    expect(tester.getRect(find.byKey(const ValueKey("composer-input"))).height,
        lessThan(200));
  });

  testWidgets("a hidden child keeps its last size", (tester) async {
    final hidden = ValueNotifier(false);
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: ValueListenableBuilder<bool>(
        valueListenable: hidden,
        builder: (context, value, _) => Column(children: [
          composerTimelineSlot(
              composerExpanded: value,
              child: const SizedBox.expand(key: timelineKey)),
          composerSlot(expanded: value, child: const SizedBox(height: 100)),
        ]),
      ),
    ));
    final shown = tester.getSize(find.byKey(timelineKey));
    hidden.value = true;
    await tester.pump();
    expect(tester.getSize(find.byKey(timelineKey)), shown);
    hidden.value = false;
    await tester.pump();
    expect(tester.getSize(find.byKey(timelineKey)), shown);
  });
}
