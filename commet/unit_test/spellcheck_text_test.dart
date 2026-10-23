import 'package:commet/utils/spellcheck/spellcheck_catalog.dart';
import 'package:commet/utils/spellcheck/spellcheck_text.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

List<String> _words(String text) =>
    [for (final r in SpellcheckText.words(text)) r.textInside(text)];

/// The text of every span that has [style], in order.
List<String> _marked(InlineSpan span, TextStyle style) {
  final out = <String>[];
  span.visitChildren((s) {
    if (s is TextSpan && s.style == style && s.text != null) out.add(s.text!);
    return true;
  });
  return out;
}

void main() {
  group("words", () {
    test("plain words, with internal apostrophes", () {
      expect(
          _words("Helo wrold, it's fine"), ["Helo", "wrold", "it's", "fine"]);
      expect(_words("don’t café naïve"), ["don’t", "café", "naïve"]);
    });

    test("skips code, links, addresses, ids and shortcodes", () {
      expect(_words("see `fooo barr` here"), ["see", "here"]);
      expect(_words("```\nlet xyzzy\n``` done"), ["done"]);
      expect(_words("go https://exmple.org/pathh now"), ["go", "now"]);
      expect(_words("[clik here](https://x.y) ok"), ["ok"]);
      expect(_words("ask @someon:nether.im or me@mial.com"), ["ask", "or"]);
      expect(_words("join #roomm:nether.im"), ["join"]);
      expect(_words("visit vommet.app soon"), ["visit", "soon"]);
      expect(_words("nice :thumbsupp: yes"), ["nice", "yes"]);
      expect(_words("/shrugg hi there"), ["hi", "there"]);
    });

    test("skips acronyms, camelCase, identifiers and single letters", () {
      expect(_words("LOL iPhone abc123 snake_case a xy"), ["xy"]);
    });
  });

  test("the word being typed is not flagged until the caret leaves it", () {
    const text = "helo wrld";
    final ranges = SpellcheckText.words(text);
    expect(
        SpellcheckText.withoutWordBeingTyped(
                ranges, const TextSelection.collapsed(offset: 9))
            .map((r) => r.textInside(text)),
        ["helo"]);
    expect(
        SpellcheckText.withoutWordBeingTyped(
                ranges, const TextSelection.collapsed(offset: 2))
            .length,
        2);
  });

  group("mark", () {
    const style = TextStyle(decoration: TextDecoration.underline);

    test("splits text spans at the marked ranges", () {
      const text = "one twoo three";
      final span = SpellcheckText.mark(const TextSpan(text: text),
          [const TextRange(start: 4, end: 8)], style);
      expect(_marked(span, style), ["twoo"]);
      expect(span.toPlainText(), text);
    });

    test("inline widgets count as one character", () {
      final span = SpellcheckText.mark(
          const TextSpan(children: [
            TextSpan(text: "hi "),
            WidgetSpan(child: SizedBox()),
            TextSpan(text: " wrold"),
          ]),
          [const TextRange(start: 5, end: 10)],
          style);
      expect(_marked(span, style), ["wrold"]);
    });

    test("code spans are left alone", () {
      final span = SpellcheckText.mark(
          const TextSpan(children: [
            TextSpan(text: "abcd", style: TextStyle(fontFamily: "code")),
            TextSpan(text: " efgh"),
          ]),
          [
            const TextRange(start: 0, end: 4),
            const TextRange(start: 5, end: 9)
          ],
          style);
      expect(_marked(span, style), ["efgh"]);
    });
  });

  group("catalog", () {
    test("picks the dictionary for a locale", () {
      expect(SpellcheckCatalog.forLocale("en_GB.UTF-8")?.code, "en_GB");
      expect(SpellcheckCatalog.forLocale("pt-BR")?.code, "pt_BR");
      expect(SpellcheckCatalog.forLocale("de")?.code, "de_DE");
      expect(SpellcheckCatalog.forLocale("en_ZZ")?.code, "en_US");
      expect(SpellcheckCatalog.forLocale("C"), isNull);
    });

    test("codes are unique", () {
      final codes = SpellcheckCatalog.all.map((l) => l.code).toList();
      expect(codes.toSet().length, codes.length);
    });
  });
}
