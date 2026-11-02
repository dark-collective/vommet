import 'package:commet/client/matrix/timeline_events/matrix_timeline_event_message.dart';
import 'package:commet/ui/atoms/rich_text/matrix_html_parser.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/dom.dart' as dom;

/// Vommet issue 24: a literal newline in `formatted_body` is whitespace
/// outside `<pre>`; only `<br>` and `<p>` break lines.

/// Stands in for LinkifyHtmlExtension (which needs a client): takes over any
/// text node containing "example.com" and lays out [renderedText], like the
/// real linkify, emoji and search-highlight extensions.
class _FakeLinkify extends HtmlExtension with TextNodeHtmlExtension {
  @override
  Set<String> get supportedTags => const {};

  @override
  bool matches(ExtensionContext context) =>
      context.node is dom.Text && context.node.text!.contains("example.com");

  @override
  InlineSpan build(ExtensionContext context) =>
      TextSpan(text: renderedText(context));
}

/// The text of every paragraph the message renders.
Future<List<String>> render(WidgetTester tester, String html) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Html(
          data: html,
          extensions: [LineBreakHtmlExtension(), _FakeLinkify()],
          style: {"blockquote": blockquoteStyle(Theme.of(context))},
        ),
      ),
    ),
  ));
  return tester
      .renderObjectList<RenderParagraph>(find.byType(RichText))
      .map((p) => p.text.toPlainText(includePlaceholders: false))
      .toList();
}

String paragraphWith(List<String> paragraphs, String word) =>
    paragraphs.firstWhere((p) => p.contains(word));

void main() {
  testWidgets("newlines around a quote's paragraph are not blank lines",
      (tester) async {
    final paragraphs =
        await render(tester, "<blockquote>\n<p>quoted</p>\n</blockquote>\n");
    expect(paragraphWith(paragraphs, "quoted").trim(), "quoted");
    expect(paragraphWith(paragraphs, "quoted"), isNot(contains("\n")));
  });

  testWidgets("a newline inside a quote's paragraph is a space",
      (tester) async {
    final paragraphs =
        await render(tester, "<blockquote><p>one\ntwo</p></blockquote>");
    expect(paragraphWith(paragraphs, "one"), contains("one two"));
  });

  testWidgets("a newline next to a linkified word is a space", (tester) async {
    final paragraphs = await render(tester, "<p>see\nexample.com\nnow</p>");
    expect(paragraphWith(paragraphs, "example.com"),
        contains("see example.com now"));
  });

  testWidgets("Element's <br>\\n gives one line break, not two",
      (tester) async {
    final paragraphs = await render(tester, "first<br>\nexample.com<br>\nlast");
    final text = paragraphWith(paragraphs, "example.com");
    expect(text, contains("first\nexample.com\nlast"));
    expect(text, isNot(contains("\n\n")));
  });

  testWidgets("<pre> keeps its newlines", (tester) async {
    final paragraphs = await render(tester, "<pre>one\nexample.com\ntwo</pre>");
    expect(paragraphWith(paragraphs, "example.com"),
        contains("one\nexample.com\ntwo"));
  });

  test("a plain-body message keeps the plain renderer", () {
    expect(
        MatrixTimelineEventMessage.usesFormattedBody(
            "m.text", {"msgtype": "m.text", "body": "one\ntwo"}, ""),
        isFalse);
    expect(
        MatrixTimelineEventMessage.usesFormattedBody(
            "m.text",
            {
              "msgtype": "m.text",
              "body": "one\ntwo",
              "format": "org.matrix.custom.html",
              "formatted_body": "one<br>\ntwo",
            },
            "one<br>\ntwo"),
        isTrue);
  });
}
