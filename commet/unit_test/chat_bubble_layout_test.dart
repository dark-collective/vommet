import 'package:commet/ui/molecules/timeline_events/layouts/timeline_event_layout_bubble.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group("chat bubble layout (Vommet issue 421)", () {
    test("own messages never show an avatar or a name", () {
      for (final direct in [true, false]) {
        expect(
            TimelineEventLayoutBubble.showsAvatarColumn(
                isOwnMessage: true, isDirectMessage: direct),
            isFalse);
        expect(
            TimelineEventLayoutBubble.showsName(
                isOwnMessage: true, isDirectMessage: direct, showSender: true),
            isFalse);
      }
    });

    test("direct messages show no avatars or names", () {
      expect(
          TimelineEventLayoutBubble.showsAvatarColumn(
              isOwnMessage: false, isDirectMessage: true),
          isFalse);
      expect(
          TimelineEventLayoutBubble.showsName(
              isOwnMessage: false, isDirectMessage: true, showSender: true),
          isFalse);
    });

    test("group rooms name the first bubble of a run only", () {
      expect(
          TimelineEventLayoutBubble.showsAvatarColumn(
              isOwnMessage: false, isDirectMessage: false),
          isTrue);
      expect(
          TimelineEventLayoutBubble.showsName(
              isOwnMessage: false, isDirectMessage: false, showSender: true),
          isTrue);
      expect(
          TimelineEventLayoutBubble.showsName(
              isOwnMessage: false, isDirectMessage: false, showSender: false),
          isFalse);
    });
  });
}
