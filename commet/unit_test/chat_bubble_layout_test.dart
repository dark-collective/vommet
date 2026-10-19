import 'package:commet/ui/molecules/timeline_events/layouts/timeline_event_layout_bubble.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const narrow = 800.0;
  const wide = TimelineEventLayoutBubble.allLeftMinWidth;

  group("chat bubble layout (Vommet issue 421)", () {
    test("own messages show no avatar or name while on the right", () {
      for (final direct in [true, false]) {
        expect(
            TimelineEventLayoutBubble.showsAvatarColumn(
                isOwnMessage: true, isDirectMessage: direct, width: narrow),
            isFalse);
        expect(
            TimelineEventLayoutBubble.showsName(
                isOwnMessage: true,
                isDirectMessage: direct,
                showSender: true,
                width: narrow),
            isFalse);
      }
    });

    test("direct messages show no avatars or names", () {
      for (final own in [true, false]) {
        for (final width in [narrow, wide]) {
          expect(
              TimelineEventLayoutBubble.showsAvatarColumn(
                  isOwnMessage: own, isDirectMessage: true, width: width),
              isFalse);
          expect(
              TimelineEventLayoutBubble.showsName(
                  isOwnMessage: own,
                  isDirectMessage: true,
                  showSender: true,
                  width: width),
              isFalse);
        }
      }
    });

    test("group rooms name the first bubble of a run only", () {
      expect(
          TimelineEventLayoutBubble.showsAvatarColumn(
              isOwnMessage: false, isDirectMessage: false, width: narrow),
          isTrue);
      expect(
          TimelineEventLayoutBubble.showsName(
              isOwnMessage: false,
              isDirectMessage: false,
              showSender: true,
              width: narrow),
          isTrue);
      expect(
          TimelineEventLayoutBubble.showsName(
              isOwnMessage: false,
              isDirectMessage: false,
              showSender: false,
              width: narrow),
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

    test("own bubbles on the left get an avatar and name in group rooms", () {
      expect(
          TimelineEventLayoutBubble.showsAvatarColumn(
              isOwnMessage: true, isDirectMessage: false, width: wide),
          isTrue);
      expect(
          TimelineEventLayoutBubble.showsName(
              isOwnMessage: true,
              isDirectMessage: false,
              showSender: true,
              width: wide),
          isTrue);
    });
  });
}
