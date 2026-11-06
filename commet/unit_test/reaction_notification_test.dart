import 'package:commet/client/components/push_notification/reaction_notification.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> reaction(String key, {Map<String, dynamic>? extra}) => {
      "m.relates_to": {
        "rel_type": "m.annotation",
        "event_id": "\$target",
        "key": key,
      },
      ...?extra,
    };

void main() {
  test("reads the reacted-to event of a reaction", () {
    expect(ReactionNotification.targetEventId(reaction("👍")), "\$target");
    expect(
        ReactionNotification.targetEventId({
          "m.relates_to": {"rel_type": "m.reference", "event_id": "\$x"}
        }),
        isNull);
    expect(ReactionNotification.targetEventId({}), isNull);
  });

  test("body names the emoji and previews the message", () {
    expect(ReactionNotification.body(reaction("👍"), "see you\n tomorrow"),
        "reacted 👍 to: see you tomorrow");
    expect(ReactionNotification.body(reaction("👍"), null),
        "reacted 👍 to: your message");
  });

  test("custom emoji show their shortcode", () {
    expect(
        ReactionNotification.emojiLabel(
            reaction("mxc://x/y", extra: {"shortcode": "blobcat"})),
        ":blobcat:");
    expect(
        ReactionNotification.emojiLabel(reaction("mxc://x/y",
            extra: {"com.beeper.reaction.shortcode": ":party:"})),
        ":party:");
    expect(ReactionNotification.emojiLabel(reaction("mxc://x/y")),
        "a custom emoji");
  });

  test("long previews are cut without splitting an emoji", () {
    final long = "😀" * 150;
    final preview = ReactionNotification.preview(long);
    expect(preview.runes.length, ReactionNotification.previewLength);
    expect(preview.endsWith("😀…"), isTrue);
  });

  test("a bridge's double-puppeted reaction is an echo", () {
    expect(
        ReactionNotification.isBridgeEcho(
            reaction("👍", extra: {"fi.mau.double_puppet_source": "x"})),
        isTrue);
    expect(ReactionNotification.isBridgeEcho(reaction("👍")), isFalse);
  });
}
