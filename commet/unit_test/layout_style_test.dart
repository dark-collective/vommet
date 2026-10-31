// Vommet: Settings › Appearance › Layout (Discord style, Telegram style,
// Custom) and the bubble rules its options feed.
import 'package:commet/config/layout_style.dart';
import 'package:commet/config/room_layout_options.dart';
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
    // The options are under Customize, closed until opened.
    expect(find.text(layoutNeedsBubbles), findsNothing);
    await tester.tap(find.byKey(const ValueKey("layout-customize")));
    await tester.pumpAndSettle();
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

  group("rooms and spaces options", () {
    Future<void> load(Map<String, Object> stored) async {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues(stored);
      await preferences.init();
    }

    test("follow the old Discord-style layout switch until set", () async {
      await load({});
      for (final p in roomLayoutOptions) {
        expect(p.value, isTrue, reason: p.key);
      }

      await load({"vommet_experiment_banner_layout": false});
      for (final p in roomLayoutOptions) {
        expect(p.value, isFalse, reason: p.key);
        expect(p.hasStoredValue, isFalse, reason: p.key);
      }
    });

    test("once set, keep their own value", () async {
      await load({"vommet_experiment_banner_layout": false});
      await resizablePanels.set(true);
      await homeBadgeCountsDms.set(false);
      expect(resizablePanels.value, isTrue);
      expect(homeBadgeCountsDms.value, isFalse);
      expect(shrinkBannersOnScroll.value, isFalse);

      await preferences.experimentBannerLayout.set(true);
      expect(homeBadgeCountsDms.value, isFalse);
      expect(shrinkBannersOnScroll.value, isTrue);

      await load({
        "vommet_experiment_banner_layout": true,
        "vommet_rooms_member_tabs": false,
      });
      expect(memberPanelTabs.value, isFalse);
      expect(memberListOnlineSections.value, isTrue);
    });

    test("picking a style leaves them alone", () async {
      await load({});
      final values = <String, bool>{};
      var on = false;
      for (final p in roomLayoutOptions) {
        on = !on;
        await p.set(on);
        values[p.key] = on;
      }
      for (final style in LayoutStyle.values) {
        await pickLayoutStyle(style);
        for (final p in roomLayoutOptions) {
          expect(p.value, values[p.key], reason: "${p.key} after $style");
        }
      }
    });

    testWidgets("changing one doesn't make the layout Custom", (
      tester,
    ) async {
      await load({});
      tester.view.physicalSize = const Size(900, 2400);
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
      expect(find.text(layoutSectionRoomsAndSpaces), findsNothing);
      await tester.tap(find.byKey(const ValueKey("layout-customize")));
      await tester.pumpAndSettle();
      expect(find.text(layoutSectionRoomsAndSpaces), findsOneWidget);

      final resize = find.byKey(ValueKey("layout-${resizablePanels.key}-0"));
      await tester.ensureVisible(resize);
      await tester.tap(resize);
      await tester.pumpAndSettle();
      expect(resizablePanels.value, isFalse);

      await tester.ensureVisible(find.text(layoutMemberListByRole));
      await tester.tap(find.text(layoutMemberListByRole));
      await tester.pumpAndSettle();
      expect(memberListOnlineSections.value, isFalse);

      expect(currentLayoutStyle, LayoutStyle.discord);
      expect(layoutStyleCustomPicked.value, isFalse);
    });

    testWidgets("Customize opens by itself while Custom is picked", (
      tester,
    ) async {
      await load({});
      await pickLayoutStyle(LayoutStyle.custom);
      tester.view.physicalSize = const Size(900, 2400);
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
      expect(find.text(layoutSectionRoomsAndSpaces), findsOneWidget);
      expect(find.text(layoutStyleBeta), findsOneWidget);
    });
  });
}
