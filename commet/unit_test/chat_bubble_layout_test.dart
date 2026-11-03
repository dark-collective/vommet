import 'package:commet/ui/atoms/thread_card.dart';
import 'package:commet/ui/molecules/timeline_events/layouts/timeline_event_layout_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiamat/config/style/theme_amoled.dart';
import 'package:tiamat/config/style/theme_dark.dart';
import 'package:tiamat/config/style/theme_extensions.dart';
import 'package:tiamat/config/style/theme_light.dart';
import 'package:tiamat/config/style/theme_nordic.dart';

void main() {
  const narrow = 800.0;
  const wide = TimelineEventLayoutBubble.allLeftMinWidth;

  group("chat bubble layout (Vommet issue 421)", () {
    test("own messages show no avatar or name while on the right", () {
      expect(
          TimelineEventLayoutBubble.showsAvatarColumn(
              isOwnMessage: true, width: narrow),
          isFalse);
      expect(
          TimelineEventLayoutBubble.showsName(
              isOwnMessage: true, showSender: true, width: narrow),
          isFalse);
    });

    test(
        "others' bubbles show avatars and names, in DMs too (Vommet issue 656)",
        () {
      for (final width in [narrow, wide]) {
        expect(
            TimelineEventLayoutBubble.showsAvatarColumn(
                isOwnMessage: false, width: width),
            isTrue);
        expect(
            TimelineEventLayoutBubble.showsName(
                isOwnMessage: false, showSender: true, width: width),
            isTrue);
      }
    });

    test("names go on the first bubble of a run only", () {
      expect(
          TimelineEventLayoutBubble.showsAvatarColumn(
              isOwnMessage: false, width: narrow),
          isTrue);
      expect(
          TimelineEventLayoutBubble.showsName(
              isOwnMessage: false, showSender: true, width: narrow),
          isTrue);
      expect(
          TimelineEventLayoutBubble.showsName(
              isOwnMessage: false, showSender: false, width: narrow),
          isFalse);
    });
  });

  group("chat bubbles on wide timelines (Vommet issue 507)", () {
    test("own bubbles go left from the threshold on", () {
      expect(
          TimelineEventLayoutBubble.ownOnRight(
              isOwnMessage: true, width: wide - 1),
          isTrue);
      expect(
          TimelineEventLayoutBubble.ownOnRight(isOwnMessage: true, width: wide),
          isFalse);
      expect(
          TimelineEventLayoutBubble.ownOnRight(
              isOwnMessage: false, width: narrow),
          isFalse);
    });

    test("own bubbles on the left get an avatar and name", () {
      expect(
          TimelineEventLayoutBubble.showsAvatarColumn(
              isOwnMessage: true, width: wide),
          isTrue);
      expect(
          TimelineEventLayoutBubble.showsName(
              isOwnMessage: true, showSender: true, width: wide),
          isTrue);
    });
  });

  group("chat bubble colours (Vommet issue 502)", () {
    test("own bubbles are readable on every built-in theme", () {
      for (final theme in [
        ThemeAmoled.theme,
        ThemeDark.theme,
        ThemeLight.theme,
      ]) {
        final colors = theme.colorScheme;
        final (bubble, _) =
            TimelineEventLayoutBubble.bubbleColors(colors, isOwnMessage: true);
        expect(
            TimelineEventLayoutBubble.contrastRatio(bubble, colors.onSurface),
            greaterThanOrEqualTo(3));
      }
    });

    test("AMOLED own bubbles are a dark shade with the surface text colour",
        () {
      final colors = ThemeAmoled.theme.colorScheme;
      final (bubble, text) =
          TimelineEventLayoutBubble.bubbleColors(colors, isOwnMessage: true);
      expect(bubble, isNot(colors.primaryContainer));
      expect(bubble.computeLuminance(), lessThan(0.1));
      expect(text, colors.onSurface);
    });

    test("a theme's picked bubble colours are used as they are (issue 532)",
        () {
      final colors = ThemeAmoled.theme.colorScheme;
      const extra = ExtraColors(
          codeHighlight: Color(0xff000000),
          linkColor: Color(0xff000000),
          ownBubble: Color(0xfff0f0f0),
          otherBubble: Color(0xff202020));
      final (own, ownText) = TimelineEventLayoutBubble.bubbleColors(colors,
          isOwnMessage: true, extra: extra);
      expect(own, const Color(0xfff0f0f0));
      // The light bubble gets the darker of text and accent text.
      expect(
          TimelineEventLayoutBubble.contrastRatio(own, ownText),
          greaterThanOrEqualTo(
              TimelineEventLayoutBubble.contrastRatio(own, colors.onSurface)));
      final (other, otherText) = TimelineEventLayoutBubble.bubbleColors(colors,
          isOwnMessage: false, extra: extra);
      expect(other, const Color(0xff202020));
      expect(otherText, colors.onSurface);
    });

    test("light themes default own bubbles to a soft blue (issue 560)", () {
      for (final theme in [ThemeLight.theme, ThemeNordic.polar]) {
        final colors = theme.colorScheme;
        final extra = theme.extension<ExtraColors>();
        final (bubble, text) = TimelineEventLayoutBubble.bubbleColors(colors,
            isOwnMessage: true, extra: extra);
        expect(bubble, TimelineEventLayoutBubble.lightOwnBubble);
        expect(TimelineEventLayoutBubble.contrastRatio(bubble, text),
            greaterThanOrEqualTo(4.5));
      }
      // A colour the theme picked still wins.
      const picked = ExtraColors(
          codeHighlight: Color(0xff000000),
          linkColor: Color(0xff000000),
          ownBubble: Color(0xffffe0e0));
      final (bubble, _) = TimelineEventLayoutBubble.bubbleColors(
          ThemeLight.theme.colorScheme,
          isOwnMessage: true,
          extra: picked);
      expect(bubble, const Color(0xffffe0e0));
    });

    test("themes with readable containers keep them", () {
      const colors = ColorScheme.dark(
          primaryContainer: Color(0xff3a3a6a),
          onPrimaryContainer: Color(0xffe0e0ff));
      expect(TimelineEventLayoutBubble.bubbleColors(colors, isOwnMessage: true),
          (colors.primaryContainer, colors.onPrimaryContainer));
      expect(
          TimelineEventLayoutBubble.bubbleColors(colors, isOwnMessage: false),
          (colors.surfaceContainerHigh, colors.onSurface));
    });
  });

  group("thread card side (Vommet issue 547)", () {
    for (final onRight in [true, false]) {
      testWidgets("sits under the bubble on the ${onRight ? "right" : "left"}",
          (tester) async {
        tester.view.physicalSize = const Size(narrow, 600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MaterialApp(
          theme: ThemeDark.theme,
          home: Scaffold(
            // As wide as the timeline, like the bubble's row makes it.
            body: SizedBox(
              width: narrow,
              child: Column(
                crossAxisAlignment:
                    onRight ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  TimelineEventLayoutBubble.threadSlot(
                      const ThreadCard(replyCount: 2, replies: []),
                      leftInset: 0),
                ],
              ),
            ),
          ),
        ));
        final card = tester.getRect(find.byKey(const ValueKey("thread-card")));
        expect(card.width,
            lessThanOrEqualTo(TimelineEventLayoutBubble.threadCardMaxWidth));
        if (onRight) {
          expect(card.right, narrow);
        } else {
          expect(card.left, 0);
        }
      });
    }
  });
}
