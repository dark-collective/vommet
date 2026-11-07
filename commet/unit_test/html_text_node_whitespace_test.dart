import 'package:commet/ui/atoms/rich_text/matrix_html_parser.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/dom.dart' as dom;

/// Stands in for LinkifyHtmlExtension (which needs a client): takes over any
/// text node containing "example.com", as bare-domain linking does.
class _FakeLinkify extends HtmlExtension with TextNodeHtmlExtension {
  @override
  Set<String> get supportedTags => const {};

  @override
  bool matches(ExtensionContext context) =>
      context.node is dom.Text && context.node.text!.contains("example.com");

  @override
  InlineSpan build(ExtensionContext context) =>
      TextSpan(text: context.node.text);
}

Future<String> render(WidgetTester tester, String html) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Html(
        data: html,
        extensions: [CodeHtmlExtension(), _FakeLinkify()],
      ),
    ),
  ));
  return tester
      .renderObjectList<RenderParagraph>(find.byType(RichText))
      .map((p) => p.text.toPlainText(includePlaceholders: false))
      .join("\n");
}

void main() {
  testWidgets("space after linkified inline code is kept", (tester) async {
    final text = await render(tester,
        "<ul><li>and plain <code>example.com</code> text turned into links</li></ul>");
    expect(text, contains("plain example.com text turned"));
  });

  testWidgets("space after a linkified bold domain is kept", (tester) async {
    final text = await render(tester, "see <b>example.com</b> for more");
    expect(text, contains("see example.com for more"));
  });

  testWidgets("plain inline code still keeps its space", (tester) async {
    final text = await render(tester, "a <code>&lt;t:1&gt;</code> times");
    expect(text, contains("a <t:1> times"));
  });
}
