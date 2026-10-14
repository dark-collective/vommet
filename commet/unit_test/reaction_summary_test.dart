import 'package:commet/ui/atoms/emoji_reaction.dart';
import 'package:commet/utils/emoji/unicode_emoji.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiamat/config/style/theme_dark.dart';

// Vommet issue 34: hovering a reaction says who reacted, right-click lists them.
void main() {
  test('names who reacted', () {
    expect(EmojiReaction.summarizeReactors([], 0), "");
    expect(EmojiReaction.summarizeReactors(["Alice"], 1), "Alice");
    expect(
        EmojiReaction.summarizeReactors(["Alice", "Bob"], 2), "Alice and Bob");
    expect(EmojiReaction.summarizeReactors(["Alice", "Bob", "Carol"], 3),
        "Alice, Bob and Carol");
    expect(EmojiReaction.summarizeReactors(["A", "B", "C"], 4),
        "A, B, C and 1 other");
    expect(EmojiReaction.summarizeReactors(["A", "B", "C"], 250),
        "A, B, C and 247 others");
    // Fewer names than promised: say only what is known, never throw.
    expect(EmojiReaction.summarizeReactors(["Alice"], 5), "Alice");
  });

  test('reaction tooltip sentences', () {
    expect(EmojiReaction.reactedWith("You and Bob", ":fire:"),
        "You and Bob reacted with :fire:");
    expect(EmojiReaction.reactedPlain("Alice"), "Alice reacted");
  });

  group('EmojiReaction gestures', () {
    late List<String> calls;

    Widget harness({String? tooltip}) => MaterialApp(
          theme: ThemeDark.theme,
          home: Scaffold(
            body: Center(
              child: EmojiReaction(
                emoji: UnicodeEmoticon("🔥", shortcode: "fire"),
                numReactions: 2,
                tooltip: tooltip,
                onTapped: (_) => calls.add("tap"),
                onLongPressed: (_) => calls.add("long"),
              ),
            ),
          ),
        );

    setUp(() => calls = []);

    testWidgets('hover shows who reacted', (tester) async {
      await tester.pumpWidget(harness(tooltip: "Alice and Bob reacted"));
      expect(find.text("Alice and Bob reacted"), findsNothing);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.byType(EmojiReaction)));
      await tester.pumpAndSettle();
      expect(find.text("Alice and Bob reacted"), findsOneWidget);

      await mouse.moveTo(Offset.zero);
      await tester.pumpAndSettle();
      expect(find.text("Alice and Bob reacted"), findsNothing);
    });

    testWidgets('long press on touch still opens the list, no tooltip',
        (tester) async {
      await tester.pumpWidget(harness(tooltip: "Alice and Bob reacted"));
      await tester.longPress(find.byType(EmojiReaction));
      await tester.pumpAndSettle();
      expect(calls, ["long"]);
      expect(find.text("Alice and Bob reacted"), findsNothing);
    });

    testWidgets('tap still toggles the reaction', (tester) async {
      await tester.pumpWidget(harness(tooltip: "Alice and Bob reacted"));
      await tester.tap(find.byType(EmojiReaction));
      await tester.pumpAndSettle();
      expect(calls, ["tap"]);
    });

    testWidgets('right click falls back to the long-press list',
        (tester) async {
      await tester.pumpWidget(harness());
      await tester.tap(find.byType(EmojiReaction),
          kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      expect(calls, ["long"]);
    });
  });
}
