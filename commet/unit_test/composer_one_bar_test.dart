import 'package:commet/client/client.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/molecules/message_effect_picker.dart';
import 'package:commet/ui/molecules/message_input.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeClient implements Client {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

// Vommet composer round 5: one bar. + and record sit inside the box,
// record turns into Send while there's text, and a picked effect rides on
// the next message only.
void main() {
  late List<String> sent;

  setUp(() async {
    // unit_test/ isn't a recognised test directory for the analyzer.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    sent = [];
  });

  tearDown(() => preferences.layoutOverride.set(null));

  Future<void> pumpComposer(WidgetTester tester, {bool voice = true}) async {
    tester.view.physicalSize = const Size(412, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: MessageInput(
            client: FakeClient(),
            availibleEmoticons: const [],
            onSendMessage: (message, {overrideClient}) {
              sent.add(message);
              return MessageInputSendResult.success;
            },
            onSendVoiceMessage:
                voice ? (recording, {overrideClient}) async => true : null,
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  Future<void> send(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
  }

  Rect rectOf(WidgetTester tester, String key) =>
      tester.getRect(find.byKey(ValueKey(key)));

  for (final layout in ["mobile", "desktop"]) {
    testWidgets("$layout: record turns into Send while there's text",
        (tester) async {
      await preferences.layoutOverride.set(layout);
      await pumpComposer(tester);
      expect(find.byIcon(Icons.mic), findsOneWidget);
      expect(find.byIcon(Icons.send), findsNothing);
      // No more ⋯ menu on an empty box.
      expect(find.byIcon(Icons.more_horiz), findsNothing);

      await tester.enterText(find.byType(TextField), "hi");
      await tester.pump();
      expect(find.byIcon(Icons.send), findsOneWidget);
      expect(find.byIcon(Icons.mic), findsNothing);

      await tester.enterText(find.byType(TextField), "");
      await tester.pump();
      expect(find.byIcon(Icons.mic), findsOneWidget);
      expect(find.byIcon(Icons.send), findsNothing);
    });

    testWidgets("$layout: + and record sit inside the box", (tester) async {
      await preferences.layoutOverride.set(layout);
      await pumpComposer(tester);
      final box = rectOf(tester, "composer-input");
      final plus = rectOf(tester, "composer-attach");
      final voice = rectOf(tester, "composer-voice");
      final field = rectOf(tester, "composer-input-field");
      expect(box.contains(plus.center), isTrue);
      expect(box.contains(voice.center), isTrue);
      expect(plus.right, lessThanOrEqualTo(field.left + 1));
      expect(voice.left, greaterThanOrEqualTo(field.right - 1));
      expect(find.byKey(const ValueKey("composer-plus")), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets("no voice messages: Send stays, grayed while empty",
      (tester) async {
    await pumpComposer(tester, voice: false);
    expect(find.byIcon(Icons.mic), findsNothing);
    expect(find.byIcon(Icons.send), findsOneWidget);
  });

  testWidgets("an effect goes with the next message only", (tester) async {
    await pumpComposer(tester);
    final state = tester.state<MessageInputState>(find.byType(MessageInput));
    state.pickEffect(MessageEffectPicker.all.first);
    await tester.pump();
    expect(find.byKey(const ValueKey("composer-effect-chip")), findsOneWidget);

    await tester.enterText(find.byType(TextField), "hi");
    await tester.pump();
    expect(find.byKey(const ValueKey("composer-send-effect-badge")),
        findsOneWidget);

    await send(tester);
    expect(sent, ["/confetti hi"]);
    expect(find.byKey(const ValueKey("composer-effect-chip")), findsNothing);
    expect(state.pendingEffect, isNull);

    await tester.enterText(find.byType(TextField), "again");
    await tester.pump();
    expect(
        find.byKey(const ValueKey("composer-send-effect-badge")), findsNothing);
    await send(tester);
    expect(sent, ["/confetti hi", "again"]);
  });

  testWidgets("the chip's × drops the effect", (tester) async {
    await pumpComposer(tester);
    final state = tester.state<MessageInputState>(find.byType(MessageInput));
    state.pickEffect(MessageEffectPicker.all.first);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey("composer-effect-chip-clear")));
    await tester.pump();
    expect(find.byKey(const ValueKey("composer-effect-chip")), findsNothing);

    await tester.enterText(find.byType(TextField), "plain");
    await tester.pump();
    await send(tester);
    expect(sent, ["plain"]);
  });
}
