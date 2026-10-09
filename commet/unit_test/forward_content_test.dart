import 'package:commet/client/matrix/forwarding/forward_content.dart';
import 'package:test/test.dart';

const _key = ForwardContent.key;

const _origin = ForwardOrigin(
  sender: "@alice:example.org",
  roomId: "!source:example.org",
  eventId: r"$original:example.org",
  originServerTs: 1722451200000,
);

const _link =
    "https://matrix.to/#/!source%3Aexample.org/%24original%3Aexample.org?via=example.org";

Map<String, dynamic> _forward(Map<String, dynamic> original,
        {bool showSender = true,
        bool hideCaption = false,
        ForwardOrigin? origin = _origin,
        String type = "m.room.message"}) =>
    ForwardContent.build(original,
        origin: origin,
        type: type,
        showSender: showSender,
        hideCaption: hideCaption,
        via: const ["example.org"],
        displayName: (id) => id == "@alice:example.org" ? "Alice" : id);

void main() {
  group("plain copy (sender hidden)", () {
    test("text is copied and mentions are cleared", () {
      final out = _forward({
        "msgtype": "m.text",
        "body": "hello @bob:example.org",
        "m.mentions": {
          "user_ids": ["@bob:example.org"]
        },
      }, showSender: false);

      expect(out["body"], "hello @bob:example.org");
      expect(out["m.mentions"], isEmpty);
      expect(out.containsKey(_key), isFalse);
    });

    test("reply relation and both reply fallbacks are removed", () {
      final out = _forward({
        "msgtype": "m.text",
        "body": "> <@bob:example.org> original\n> second line\n\nmy answer",
        "format": "org.matrix.custom.html",
        "formatted_body":
            "<mx-reply><blockquote>In reply to <a>bob</a><br>original</blockquote></mx-reply><b>my answer</b>",
        "m.relates_to": {
          "m.in_reply_to": {"event_id": r"$abc"}
        },
      }, showSender: false);

      expect(out.containsKey("m.relates_to"), isFalse);
      expect(out["body"], "my answer");
      expect(out["formatted_body"], "<b>my answer</b>");
    });

    test("a quote that is not a reply is left alone", () {
      const body = "> <@bob:example.org> said this\n\nand I agree";
      final out =
          _forward({"msgtype": "m.text", "body": body}, showSender: false);

      expect(out["body"], body);
    });

    test("thread, edit content and per-message profiles are removed", () {
      final out = _forward({
        "msgtype": "m.text",
        "body": "in a thread",
        "m.relates_to": {"rel_type": "m.thread", "event_id": r"$root"},
        "m.new_content": {"msgtype": "m.text", "body": "x"},
        "com.beeper.per_message_profile": {"displayname": "Someone"},
        "m.per_message_profile": {"displayname": "Someone"},
      }, showSender: false);

      expect(out.keys, unorderedEquals(["msgtype", "body", "m.mentions"]));
    });

    test("forwarding a forward with the sender hidden copies the original", () {
      final forwarded = _forward({"msgtype": "m.text", "body": "hi"});
      final out = _forward(forwarded, showSender: false);

      expect(out["body"], "hi");
      expect(out.containsKey(_key), isFalse);
      expect(out.containsKey("format"), isFalse);
    });

    test("stickers are always a plain copy", () {
      final out = _forward({"body": "cat", "url": "mxc://example.org/cat"},
          type: "m.sticker");

      expect(out.containsKey(_key), isFalse);
      expect(out["url"], "mxc://example.org/cat");
    });
  });

  group("forward with the sender shown (MSC4553)", () {
    test("text gets a fallback and keeps the original under the key", () {
      final out = _forward({
        "msgtype": "m.text",
        "body": "Meeting starts at noon.",
        "format": "org.matrix.custom.html",
        "formatted_body": "<p>Meeting starts at noon.</p>",
        "m.mentions": {
          "user_ids": ["@bob:example.org"]
        },
      });

      expect(out["body"],
          "Forwarded from @alice:example.org - view original message: $_link\nMeeting starts at noon.");
      expect(
          out["formatted_body"],
          '<strong>Forwarded from <a href="https://matrix.to/#/%40alice%3Aexample.org">@alice:example.org</a>'
          ' - <a href="$_link">view original message</a></strong>'
          "<br><blockquote><p>Meeting starts at noon.</p></blockquote>");
      expect(out["m.mentions"], isEmpty);

      final forwarded = out[_key] as Map;
      expect(forwarded["sender"], "@alice:example.org");
      expect(forwarded["room_id"], "!source:example.org");
      expect(forwarded["event_id"], r"$original:example.org");
      expect(forwarded["origin_server_ts"], 1722451200000);
      expect((forwarded["content"] as Map)["body"], "Meeting starts at noon.");
      expect((forwarded["content"] as Map)["m.mentions"], isNotNull,
          reason: "the original content is copied unchanged");
    });

    test("without an origin the fallback says Forwarded message", () {
      final out =
          _forward({"msgtype": "m.text", "body": "hello"}, origin: null);

      expect(out["body"], "Forwarded message\nhello");
      expect(out["formatted_body"],
          "<strong>Forwarded message</strong><br><blockquote>hello</blockquote>");
    });

    test("plain text is escaped in the HTML fallback", () {
      final out = _forward({"msgtype": "m.text", "body": "a < b\nc"});

      expect(out["formatted_body"],
          endsWith("<blockquote>a &lt; b<br>c</blockquote>"));
    });

    test("forwarding a forward points at the first message", () {
      final first = _forward({"msgtype": "m.text", "body": "hi"});
      final second = _forward(first,
          origin: const ForwardOrigin(
              sender: "@carol:example.org",
              roomId: "!middle:example.org",
              eventId: r"$middle:example.org"));

      expect((second[_key] as Map)["sender"], "@alice:example.org");
      expect((second[_key] as Map)["event_id"], r"$original:example.org");
      expect(((second[_key] as Map)["content"] as Map)["body"], "hi");
      expect(second["body"], startsWith("Forwarded from @alice:example.org"));
    });

    test("an emote is sent as text naming the original sender", () {
      final out = _forward({"msgtype": "m.emote", "body": "waves"});

      expect(out["msgtype"], "m.text");
      expect(out["body"], endsWith("\nAlice waves"));
      expect(
          out["formatted_body"],
          endsWith(
              '<blockquote><em><strong><a href="https://matrix.to/#/%40alice%3Aexample.org">Alice</a></strong> waves</em></blockquote>'));
      expect(((out[_key] as Map)["content"] as Map)["msgtype"], "m.emote");
    });

    test("media without a caption: the filename moves, no quote", () {
      final out = _forward({
        "msgtype": "m.file",
        "body": "agenda.pdf",
        "url": "mxc://example.org/agenda",
      });

      expect(out["filename"], "agenda.pdf");
      expect(out["url"], "mxc://example.org/agenda");
      expect(out["body"],
          "Forwarded from @alice:example.org - view original message: $_link");
      expect(out["formatted_body"], isNot(contains("blockquote")));
    });

    test("media with a caption quotes the caption", () {
      final out = _forward({
        "msgtype": "m.image",
        "body": "I'll just leave this here...",
        "filename": "lisa.png",
        "file": {"url": "mxc://example.org/lisa"},
      });

      expect(out["filename"], "lisa.png");
      expect(out["body"], endsWith("\nI'll just leave this here..."));
      expect(out["file"], {"url": "mxc://example.org/lisa"});
    });

    test("hide caption drops the caption from both copies", () {
      final out = _forward({
        "msgtype": "m.image",
        "body": "I'll just leave this here...",
        "filename": "lisa.png",
        "format": "org.matrix.custom.html",
        "formatted_body": "<i>I'll just leave this here...</i>",
        "url": "mxc://example.org/lisa",
      }, hideCaption: true);

      expect(out["body"], isNot(contains("leave this")));
      expect(out["formatted_body"], isNot(contains("leave this")));
      final original = (out[_key] as Map)["content"] as Map;
      expect(original["body"], "lisa.png");
      expect(original.containsKey("formatted_body"), isFalse);
    });

    test("hide caption also works on a plain copy", () {
      final out = _forward({
        "msgtype": "m.image",
        "body": "caption",
        "filename": "lisa.png",
        "url": "mxc://example.org/lisa",
      }, showSender: false, hideCaption: true);

      expect(out["body"], "lisa.png");
      expect(out.containsKey("filename"), isFalse);
    });

    test("a location keeps its own body", () {
      final out = _forward({
        "msgtype": "m.location",
        "body": "Big Ben",
        "geo_uri": "geo:51.5008,0.1247",
      });

      expect(out["body"], "Big Ben");
      expect(out.containsKey(_key), isTrue);
    });
  });

  group("reading forwards", () {
    test("displayContent renders the original, not the fallback", () {
      final sent = _forward({
        "msgtype": "m.text",
        "body": "hi",
        "m.relates_to": {"rel_type": "m.thread", "event_id": r"$x"},
        "m.mentions": {
          "user_ids": ["@bob:example.org"]
        },
      });
      final shown = ForwardContent.displayContent(sent)!;

      expect(shown["body"], "hi");
      expect(shown.containsKey("m.relates_to"), isFalse);
      expect(shown["m.mentions"], isEmpty);
      expect(ForwardContent.originOf(shown)?.sender, "@alice:example.org");
    });

    test("displayContent keeps the forward's own relation", () {
      final sent = _forward({"msgtype": "m.text", "body": "hi"});
      sent["m.relates_to"] = {"rel_type": "m.thread", "event_id": r"$here"};

      expect(ForwardContent.displayContent(sent)!["m.relates_to"],
          {"rel_type": "m.thread", "event_id": r"$here"});
    });

    test("displayContent turns an emote into text with the actor", () {
      final sent = _forward({"msgtype": "m.emote", "body": "waves"});
      final shown =
          ForwardContent.displayContent(sent, displayName: (id) => "Alice")!;

      expect(shown["msgtype"], "m.text");
      expect(shown["body"], "Alice waves");
    });

    test("an invalid copy falls back to the top-level content", () {
      expect(
          ForwardContent.displayContent({
            "msgtype": "m.text",
            "body": "Forwarded message\nhi",
            _key: {"content": "nope"},
          }),
          isNull);
    });

    test("MSC2723 forwards are recognised but carry no copy", () {
      final content = {
        "msgtype": "m.text",
        "body": "hi",
        ForwardContent.famedlyKey: {"sender": "@alice:example.org"},
      };

      expect(ForwardContent.isForward(content), isTrue);
      expect(ForwardContent.originOf(content)?.sender, "@alice:example.org");
      expect(ForwardContent.displayContent(content), isNull);
    });

    test("ordinary messages are not forwards", () {
      expect(ForwardContent.isForward({"msgtype": "m.text", "body": "hi"}),
          isFalse);
    });

    test("captions are detected only on media", () {
      expect(
          ForwardContent.hasCaption(
              {"msgtype": "m.image", "body": "c", "filename": "a.png"}),
          isTrue);
      expect(
          ForwardContent.hasCaption(
              {"msgtype": "m.image", "body": "a.png", "filename": "a.png"}),
          isFalse);
      expect(ForwardContent.hasCaption({"msgtype": "m.image", "body": "a.png"}),
          isFalse);
      expect(
          ForwardContent.hasCaption(
              {"msgtype": "m.text", "body": "c", "filename": "a"}),
          isFalse);
    });
  });

  test("the original map is not modified", () {
    final original = {
      "msgtype": "m.image",
      "body": "caption",
      "filename": "a.png",
      "m.relates_to": {
        "m.in_reply_to": {"event_id": r"$x"}
      },
    };
    _forward(original, hideCaption: true);

    expect(original["body"], "caption");
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
  });
}
