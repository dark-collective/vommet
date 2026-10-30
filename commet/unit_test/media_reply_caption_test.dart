import 'package:commet/client/matrix/timeline_events/matrix_timeline_event_message.dart';
import 'package:flutter_test/flutter_test.dart';

// Vommet issue 530: a captioned picture sent as a bridged reply lost its
// caption, because its m.mentions sent it down the (empty) HTML path.
void main() {
  bool usesHtml(Map<String, dynamic> content, {String formattedText = ""}) =>
      MatrixTimelineEventMessage.usesFormattedBody(
          content["msgtype"] as String, content, formattedText);

  // Shaped like the event in the issue: caption in body, a reply with
  // m.mentions, an encrypted file and no thumbnail.
  final bridgedReply = <String, dynamic>{
    "msgtype": "m.image",
    "body": "look at this",
    "filename": "image.jpg",
    "file": {
      "url": "mxc://example.org/abc",
      "v": "v2",
      "key": {"kty": "oct", "k": "abc", "alg": "A256CTR", "ext": true},
      "iv": "AAAAAAAAAAAAAAAAAAAAAA",
      "hashes": {"sha256": "abc"},
    },
    "info": {"mimetype": "image/jpeg", "w": 800, "h": 600, "size": 1234},
    "m.relates_to": {
      "m.in_reply_to": {"event_id": "\$parent:example.org"},
    },
    "m.mentions": {
      "user_ids": ["@alice:example.org"],
    },
    "com.beeper.disappearing_timer": {"timer": 0},
  };

  test("a captioned media reply with mentions keeps its plain caption", () {
    expect(usesHtml(bridgedReply), isFalse);
  });

  test("media with an HTML caption still renders it", () {
    final content = {
      ...bridgedReply,
      "format": "org.matrix.custom.html",
      "formatted_body": "<b>look</b> at this",
    };
    expect(usesHtml(content, formattedText: "<b>look</b> at this"), isTrue);
  });

  test("media with format but an empty formatted body uses the plain caption",
      () {
    final content = {...bridgedReply, "format": "org.matrix.custom.html"};
    expect(usesHtml(content), isFalse);
  });

  test("text messages keep the HTML path for mentions", () {
    final content = <String, dynamic>{
      "msgtype": "m.text",
      "body": "hi alice",
      "m.mentions": {
        "user_ids": ["@alice:example.org"],
      },
    };
    expect(usesHtml(content), isTrue);
    expect(usesHtml({"msgtype": "m.text", "body": "hi"}), isFalse);
  });
}
