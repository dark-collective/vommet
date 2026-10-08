import 'package:commet/client/matrix/forwarding/forward_content.dart';
import 'package:test/test.dart';

void main() {
  test("plain text is copied and mentions are cleared", () {
    final out = ForwardContent.build({
      "msgtype": "m.text",
      "body": "hello @alice:example.org",
      "m.mentions": {
        "user_ids": ["@alice:example.org"]
      },
    });

    expect(out["msgtype"], "m.text");
    expect(out["body"], "hello @alice:example.org");
    expect(out["m.mentions"], isEmpty);
  });

  test("reply relation and both reply fallbacks are removed", () {
    final out = ForwardContent.build({
      "msgtype": "m.text",
      "body": "> <@bob:example.org> original\n> second line\n\nmy answer",
      "format": "org.matrix.custom.html",
      "formatted_body":
          "<mx-reply><blockquote>In reply to <a>bob</a><br>original</blockquote></mx-reply><b>my answer</b>",
      "m.relates_to": {
        "m.in_reply_to": {"event_id": r"$abc"}
      },
    });

    expect(out.containsKey("m.relates_to"), isFalse);
    expect(out["body"], "my answer");
    expect(out["formatted_body"], "<b>my answer</b>");
  });

  test("a quote that is not a reply is left alone", () {
    const body = "> <@bob:example.org> said this\n\nand I agree";
    final out = ForwardContent.build({"msgtype": "m.text", "body": body});

    expect(out["body"], body);
  });

  test("thread relation, edit content and per-message profile are removed", () {
    final out = ForwardContent.build({
      "msgtype": "m.text",
      "body": "in a thread",
      "m.relates_to": {"rel_type": "m.thread", "event_id": r"$root"},
      "m.new_content": {"msgtype": "m.text", "body": "x"},
      "com.beeper.per_message_profile": {"displayname": "Someone"},
      "m.per_message_profile": {"displayname": "Someone"},
    });

    expect(out.keys, unorderedEquals(["msgtype", "body", "m.mentions"]));
  });

  test("media content keeps its file and info", () {
    final file = {"url": "mxc://example.org/abc", "key": {}, "iv": "x"};
    final out = ForwardContent.build({
      "msgtype": "m.image",
      "body": "cat.png",
      "file": file,
      "info": {"w": 10, "h": 10},
    });

    expect(out["file"], file);
    expect(out["info"], {"w": 10, "h": 10});
  });

  test("the original map is not modified", () {
    final original = {
      "msgtype": "m.text",
      "body": "hi",
      "m.relates_to": {"rel_type": "m.thread", "event_id": r"$root"},
    };
    ForwardContent.build(original);

    expect(original.containsKey("m.relates_to"), isTrue);
    expect(original.containsKey("m.mentions"), isFalse);
  });

  test("only messages and stickers can be forwarded", () {
    expect(ForwardContent.canForward("m.room.message", {"msgtype": "m.text"}),
        isTrue);
    expect(
        ForwardContent.canForward("m.sticker", {"url": "mxc://a/b"}), isTrue);
    expect(ForwardContent.canForward("m.room.message", {}), isFalse);
    expect(ForwardContent.canForward("m.room.encrypted", {}), isFalse);
    expect(ForwardContent.canForward("org.matrix.msc3381.poll.start", {}),
        isFalse);
  });
}
