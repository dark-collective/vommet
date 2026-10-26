import 'package:commet/client/client.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/random_emoji_button.dart';
import 'package:commet/ui/molecules/message_input.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeClient implements Client {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

// Vommet: on phones the composer's own buttons drop under the text once the
// draft wraps, so the text gets the full width of the box.
void main() {
  setUp(() async {
    // unit_test/ isn't a recognised test directory for the analyzer.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });

  tearDown(() => preferences.layoutOverride.set(null));

  Future<void> pumpComposer(WidgetTester tester) async {
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
            onSendMessage: (message, {overrideClient}) =>
                MessageInputSendResult.success,
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  const long = "Also the photos from Saturday are up in the shared album. "
      "Tell me which ones you want printed and I'll order them tomorrow!";

  Rect emojiRect(WidgetTester tester) =>
      tester.getRect(find.byType(RandomEmojiButton));
  Rect fieldRect(WidgetTester tester) =>
      tester.getRect(find.byType(EditableText));

  testWidgets('phone: buttons move under a wrapping draft and back',
      (tester) async {
    await preferences.layoutOverride.set("mobile");
    await pumpComposer(tester);
    final field = find.byType(TextField);

    await tester.enterText(field, 'See you at 6?');
    await tester.pump();
    final editable = tester.state<EditableTextState>(find.byType(EditableText));
    expect(emojiRect(tester).left, greaterThan(fieldRect(tester).right - 1));
    final shortWidth = fieldRect(tester).width;

    await tester.enterText(field, long);
    await tester.pump();
    expect(emojiRect(tester).top,
        greaterThanOrEqualTo(fieldRect(tester).bottom - 1));
    expect(fieldRect(tester).width, greaterThan(shortWidth + 30));
    // Same field (no rebuild from scratch), so focus and cursor stay.
    expect(tester.state<EditableTextState>(find.byType(EditableText)),
        same(editable));
    expect(editable.widget.focusNode.hasFocus, isTrue);

    await tester.enterText(field, 'ok');
    await tester.pump();
    expect(emojiRect(tester).left, greaterThan(fieldRect(tester).right - 1));
    expect(tester.state<EditableTextState>(find.byType(EditableText)),
        same(editable));
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone: a line break moves the buttons too', (tester) async {
    await preferences.layoutOverride.set("mobile");
    await pumpComposer(tester);
    await tester.enterText(find.byType(TextField), 'one\ntwo');
    await tester.pump();
    expect(emojiRect(tester).top,
        greaterThanOrEqualTo(fieldRect(tester).bottom - 1));
  });

  testWidgets('desktop keeps the buttons beside a long draft', (tester) async {
    await preferences.layoutOverride.set("desktop");
    await pumpComposer(tester);
    await tester.enterText(find.byType(TextField), long);
    await tester.pump();
    expect(emojiRect(tester).left, greaterThan(fieldRect(tester).right - 1));
  });

  testWidgets('phone: a very long draft scrolls instead of overflowing',
      (tester) async {
    await preferences.layoutOverride.set("mobile");
    await pumpComposer(tester);
    await tester.enterText(
        find.byType(TextField), List.filled(20, long).join("\n"));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(RandomEmojiButton), findsOneWidget);
  });
}
