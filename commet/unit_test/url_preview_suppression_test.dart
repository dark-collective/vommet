import 'package:commet/client/components/url_preview/url_preview_suppression.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event_message.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: implementation_imports
import 'package:matrix/src/utils/markdown.dart' as mx_markdown;

// Vommet issue 352: <url> sends a link without a preview.
void main() {
  bool allows(String body, String link, {Map<String, dynamic>? content}) =>
      UrlPreviewSuppression(body, content: content)
          .allowsPreview(Uri.parse(link));

  test("a bare link gets a preview", () {
    expect(allows("look https://example.org", "https://example.org"), isTrue);
  });

  test("a link in angle brackets gets no preview", () {
    expect(
        allows("look <https://example.org>", "https://example.org"), isFalse);
    expect(allows("<www.example.org/a?b=c>", "www.example.org/a?b=c"), isFalse);
  });

  test("only the wrapped link loses its preview", () {
    const body = "<https://a.example> and https://b.example";
    expect(allows(body, "https://a.example"), isFalse);
    expect(allows(body, "https://b.example"), isTrue);
  });

  test("a wrapped link ending in punctuation gets no preview", () {
    expect(allows("<https://example.org/page.>", "https://example.org/page"),
        isFalse);
  });

  test("a link also written bare keeps its preview", () {
    expect(allows("<https://a.example> https://a.example", "https://a.example"),
        isTrue);
  });

  test("a wrapped link doesn't hide a longer bare one", () {
    expect(
        allows("<https://a.example> https://a.example/page",
            "https://a.example/page"),
        isTrue);
  });

  test("timestamps and mentions in angle brackets are left alone", () {
    const body = "<t:1760000000:R> <@bob:example.org> https://example.org";
    expect(allows(body, "https://example.org"), isTrue);
  });

  test("filter keeps the order of the allowed links", () {
    final links = [
      Uri.parse("https://a.example"),
      Uri.parse("https://b.example"),
      Uri.parse("https://c.example"),
    ];
    expect(
        UrlPreviewSuppression("https://a.example <https://b.example> "
                "https://c.example")
            .filter(links),
        [links[0], links[2]]);
  });

  group("MSC4095", () {
    test("an empty list means no previews", () {
      expect(
          allows("https://example.org", "https://example.org",
              content: {"com.beeper.linkpreviews": []}),
          isFalse);
      expect(
          allows("https://example.org", "https://example.org",
              content: {"m.url_previews": []}),
          isFalse);
    });

    test("only listed links get a preview", () {
      final content = {
        "m.url_previews": [
          {"matched_url": "https://a.example", "og:title": "A"},
        ],
      };
      const body = "https://a.example https://b.example";
      expect(allows(body, "https://a.example", content: content), isTrue);
      expect(allows(body, "https://b.example", content: content), isFalse);
    });

    test("no list changes nothing", () {
      expect(
          allows("https://example.org", "https://example.org",
              content: {"msgtype": "m.text"}),
          isTrue);
    });
  });

  group("allLinksSuppressed (sender side)", () {
    test("every link wrapped", () {
      expect(
          UrlPreviewSuppression.allLinksSuppressed(
              "<https://a.example> <https://b.example>"),
          isTrue);
    });

    test("one bare link, or no links", () {
      expect(
          UrlPreviewSuppression.allLinksSuppressed(
              "<https://a.example> https://b.example"),
          isFalse);
      expect(UrlPreviewSuppression.allLinksSuppressed("no links <t:1:R>"),
          isFalse);
    });
  });

  group("what the composer sends", () {
    // The composer's markdown escapes <url> instead of linking it, so the
    // formatted body has "&lt;https://...&gt;"; getLinks must still find
    // the address itself.
    List<String> previewed(String body) {
      final html = mx_markdown.markdown(body);
      final links = MatrixTimelineEventMessage.findLinks(html) ?? [];
      return UrlPreviewSuppression(body)
          .filter(links)
          .map((e) => e.toString())
          .toList();
    }

    test("getLinks reads escaped links whole", () {
      final html = mx_markdown.markdown(
          "**x** <https://a.example/page> https://b.example/?a=1&b=2");
      expect(
          MatrixTimelineEventMessage.findLinks(html)!.map((e) => e.toString()),
          ["https://a.example/page", "https://b.example/?a=1&b=2"]);
    });

    test("wrapped links are left out, bare ones previewed", () {
      expect(previewed("see <https://a.example/page> and https://b.example"),
          ["https://b.example"]);
      expect(previewed("**see** <https://a.example/?a=1&b=2>"), isEmpty);
      expect(previewed("<https://a.example>"), isEmpty);
    });

    test("the reply fallback's links don't count", () {
      expect(
          MatrixTimelineEventMessage.findLinks(
              "<mx-reply><a href=\"https://matrix.to/#/!r\">In reply to</a> "
              "https://quoted.example</mx-reply>hi"),
          isNull);
    });
  });
}
