// Vommet: Settings › Appearance › Layout (Discord style, Telegram style,
// Custom) and the bubble rules its options feed.
import 'package:commet/config/layout_style.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/molecules/timeline_events/layouts/timeline_event_layout_bubble.dart';
import 'package:commet/ui/organisms/unified_chat_list/unified_chat_list_preference.dart';
import 'package:commet/ui/pages/settings/categories/app/layout_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_dark.dart';

void main() {
  setUp(() async {
    // unit_test/ isn't a directory the analyzer counts as tests.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });

  group("layout styles", () {
    test("a fresh install is Discord style", () {
      expect(currentLayoutStyle, LayoutStyle.discord);
      expect(LayoutOptions.current.looksLike(LayoutOptions.discord), isTrue);
    });

    test("Telegram style turns every option on", () async {
      await pickLayoutStyle(LayoutStyle.telegram);
      expect(currentLayoutStyle, LayoutStyle.telegram);
      expect(experimentUnifiedChatList.value, isTrue);
      expect(captionBelowMedia.value, isTrue);
      expect(limitMessageWidth.value, isTrue);
      expect(preferences.chatBubbleLayout.value, isTrue);
      expect(OwnBubbleSide.current, OwnBubbleSide.right);
      expect(avatarAtBottomOfGroup.value, isTrue);

      await pickLayoutStyle(LayoutStyle.discord);
      expect(currentLayoutStyle, LayoutStyle.discord);
      expect(experimentUnifiedChatList.value, isFalse);
      expect(preferences.chatBubbleLayout.value, isFalse);
    });

    test("a mix of options is Custom", () async {
      await experimentUnifiedChatList.set(true);
      expect(currentLayoutStyle, LayoutStyle.custom);
    });

    test("Custom keeps the options and stays picked", () async {
      await pickLayoutStyle(LayoutStyle.telegram);
      await pickLayoutStyle(LayoutStyle.custom);
      expect(currentLayoutStyle, LayoutStyle.custom);
      expect(captionBelowMedia.value, isTrue);
    });

    test("your bubbles' side only matters with bubbles on", () {
      const a = LayoutOptions.discord;
      const b = LayoutOptions(
        oneChatList: false,
        captionBelow: false,
        limitWidth: false,
        bubbles: false,
        ownSide: OwnBubbleSide.right,
        avatarAtBottom: false,
      );
      expect(b.style, LayoutStyle.discord);
      expect(a.looksLike(b), isTrue);
    });
  });

  group("bubble options", () {
    const narrow = 800.0;
    const wide = TimelineEventLayoutBubble.allLeftMinWidth;

    test("always right keeps your bubbles right in wide windows", () {
      expect(
        TimelineEventLayoutBubble.ownOnRight(
          isOwnMessage: true,
          width: wide,
          side: OwnBubbleSide.right,
        ),
        isTrue,
      );
      expect(
        TimelineEventLayoutBubble.ownOnRight(isOwnMessage: true, width: wide),
        isFalse,
      );
      expect(
        TimelineEventLayoutBubble.ownOnRight(
          isOwnMessage: true,
          width: narrow,
          side: OwnBubbleSide.left,
        ),
        isFalse,
      );
      expect(
        TimelineEventLayoutBubble.ownOnRight(
          isOwnMessage: false,
          width: narrow,
          side: OwnBubbleSide.right,
        ),
        isFalse,
      );
    });

    test("a limited width caps the bubbles", () {
      expect(TimelineEventLayoutBubble.maxBubbleWidth(400), 300);
      expect(
        TimelineEventLayoutBubble.maxBubbleWidth(
          2000,
          limit: LayoutOptions.maxMessageWidth,
        ),
        LayoutOptions.maxMessageWidth,
      );
      expect(
        TimelineEventLayoutBubble.maxBubbleWidth(
          400,
          limit: LayoutOptions.maxMessageWidth,
        ),
        300,
      );
    });
  });

  testWidgets("the Layout panel picks a style and greys out bubble options", (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeDark.theme,
        home: const Scaffold(
          body: SingleChildScrollView(child: LayoutSettings()),
        ),
      ),
    );
    expect(find.text(layoutNeedsBubbles), findsOneWidget);

    await tester.tap(
      find.byKey(ValueKey("choice-card-${LayoutStyle.telegram}")),
    );
    await tester.pumpAndSettle();
    expect(currentLayoutStyle, LayoutStyle.telegram);
    expect(find.text(layoutNeedsBubbles), findsNothing);

    await tester.tap(find.text(layoutCaptionsAbove));
    await tester.pumpAndSettle();
    expect(captionBelowMedia.value, isFalse);
    expect(currentLayoutStyle, LayoutStyle.custom);
    expect(find.text(layoutSettingsCustomHelp), findsOneWidget);
  });
}
