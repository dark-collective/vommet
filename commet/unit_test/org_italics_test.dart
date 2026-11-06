import 'package:commet/utils/org_italics.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: implementation_imports
import 'package:matrix/src/utils/markdown.dart' as sdk_markdown;

void main() {
  final rewritten = [
    ("/this/", "*this*"),
    ("make /this/ italic", "make *this* italic"),
    ("/two words/ here", "*two words* here"),
    ("end of sentence /here/.", "end of sentence *here*."),
    ("(/aside/)", "(*aside*)"),
    ("> /quoted/", "> *quoted*"),
    ("- /item/", "- *item*"),
    ("/a/ and /b/", "*a* and *b*"),
    ("||/spoiler/||", "||*spoiler*||"),
    ("line one\n/line two/", "line one\n*line two*"),
    ("look in /etc/ for it", "look in *etc* for it"),
  ];

  final unchanged = [
    "and/or",
    "s/teh/the/",
    "/usr/bin/foo",
    "https://example.com/path/ ok",
    "see https://example.com/a/b/",
    "1/2/3",
    "/ not italic /",
    "a / b / c",
    "escaped \\/not\\/ italic",
    "`/code/`",
    "text `/code/` text",
    "[link](/path/)",
    "```\n/fenced/\n```",
    "    /indented code/",
    "/a*b/",
    "/multi\nline/",
    "no slashes at all",
    "/me waves",
  ];

  for (final (input, expected) in rewritten) {
    test("rewrites ${input.replaceAll('\n', '\\n')}", () {
      final result = orgItalicsToMarkdown(input);
      expect(result, expected);
      expect(result.length, input.length);
    });
  }

  for (final input in unchanged) {
    test("leaves ${input.replaceAll('\n', '\\n')}", () {
      expect(orgItalicsToMarkdown(input), input);
    });
  }

  test("text after a fenced block is rewritten again", () {
    expect(orgItalicsToMarkdown("```\n/a/\n```\n/b/"), "```\n/a/\n```\n*b*");
  });

  // Vommet issue 433: `>` only starts a quote when followed by a space.
  final escaped = [
    (">_>", "\\>_>"),
    (" >_>", " \\>_>"),
    (">.<", "\\>.<"),
    (">>_>", "\\>>_>"),
    ("> >_>", "> \\>_>"),
    ("hi\n>_>", "hi\n\\>_>"),
  ];

  final quotes = [
    "> quoted",
    ">> nested",
    "> a\n>\n> b",
    ">",
    "\\>_>",
    "a >_> b",
    "`>_>`",
    "```\n>_>\n```",
    "    >_> code",
  ];

  for (final (input, expected) in escaped) {
    test("escapes ${input.replaceAll('\n', '\\n')}", () {
      expect(escapeNonQuoteGreaterThan(input), expected);
    });
  }

  for (final input in quotes) {
    test("keeps ${input.replaceAll('\n', '\\n')}", () {
      expect(escapeNonQuoteGreaterThan(input), input);
    });
  }

  test(">_> is sent as plain text, > text as a quote", () {
    String html(String text) =>
        sdk_markdown.markdown(escapeNonQuoteGreaterThan(text));
    expect(html(">_>"), isNot(contains("<blockquote>")));
    expect(html(">_>"), contains("&gt;_&gt;"));
    expect(html("> quoted text"), contains("<blockquote>"));
  });
}
