import 'package:commet/ui/molecules/composer_translation.dart';
import 'package:commet/utils/translation/paragraph_translation.dart';
import 'package:flutter_test/flutter_test.dart';

// Vommet phone composer round 3: translating per paragraph, on send.
void main() {
  group("splitting", () {
    test("paragraphs are lines", () {
      expect(draftParagraphs("a\nb\n"), ["a", "b", ""]);
      expect(paragraphAt("ab\ncd", 0), 0);
      expect(paragraphAt("ab\ncd", 2), 0);
      expect(paragraphAt("ab\ncd", 3), 1);
      expect(paragraphAt("ab\ncd", 99), 1);
      expect(paragraphRanges("ab\n\ncde"),
          [(start: 0, end: 2), (start: 3, end: 3), (start: 4, end: 7)]);
    });
  });

  group("carrying targets across edits", () {
    test("typing in a paragraph keeps its target", () {
      expect(carryTargets(["hel", "x"], ["es", "de"], ["hello", "x"]),
          ["es", "de"]);
    });

    test("a new paragraph inherits the one above", () {
      expect(carryTargets(["hello"], ["es"], ["hello", ""]), ["es", "es"]);
      expect(carryTargets(["a", "b"], ["es", "de"], ["a", "", "b"]),
          ["es", "es", "de"]);
    });

    test("splitting a paragraph: both halves keep its target", () {
      expect(carryTargets(["ab", "z"], [null, "de"], ["a", "b", "z"]),
          [null, null, "de"]);
      expect(carryTargets(["ab"], ["es"], ["a", "b"]), ["es", "es"]);
    });

    test("deleting a paragraph drops its target", () {
      expect(carryTargets(["a", "b", "c"], ["es", "de", "fr"], ["a", "c"]),
          ["es", "fr"]);
    });

    test("short or missing old targets read as none", () {
      expect(carryTargets(["a", "b"], const [], ["a", "b", "c"]),
          [null, null, null]);
    });
  });

  group("resolving targets", () {
    test("own target, else the room's, never blanks or Don't translate", () {
      expect(
          resolveTargets(
              ["a", " ", "b", "c"], [null, "de", keepAsWritten, "fr"],
              fallback: "es"),
          ["es", null, null, "fr"]);
      expect(resolveTargets(["a", "b"], [null, "de"]), [null, "de"]);
    });

    test("tapping 文A: the usual language, or ask (no dead end)", () {
      expect(tapTarget(usual: "es", from: "en"), "es");
      expect(tapTarget(usual: "en", from: "en"), isNull);
      expect(tapTarget(usual: null, from: "en"), isNull);
    });
  });

  group("assembling what's sent", () {
    test("runs with the same language go together", () {
      final lines = ["hi", "there", "", "hallo", "bye"];
      final blocks = sendBlocks(lines, ["es", "es", null, "de", null]);
      expect(blocks.map((b) => (b.first, b.number, b.text, b.to)), [
        (0, 1, "hi\nthere", "es"),
        (2, 3, "", null),
        (3, 3, "hallo", "de"),
        (4, 4, "bye", null),
      ]);
      expect(assembleSend(blocks, {0: "hola\nahí", 3: "hallo!"}),
          "hola\nahí\n\nhallo!\nbye");
    });

    test("nothing translated: sent as written", () {
      final lines = ["a", "b"];
      expect(assembleSend(sendBlocks(lines, [null, null]), const {}), "a\nb");
    });

    test("errors name the paragraph and language", () {
      const block = SendBlock(first: 3, number: 2, text: "x", to: "de");
      expect(ComposerTranslation.paragraphError(block, "No model."),
          "Paragraph 2 (German): No model.");
    });

    test("languages sent in", () {
      expect(joinLanguages(["es", "de", "es"]), "es+de");
      expect(splitLanguages("es+de"), ["es", "de"]);
      expect(languageNames("es+de"), "Spanish + German");
      expect(languageNames("es"), "Spanish");
    });
  });

  test("menu languages: room's first, then recent, reachable only", () {
    expect(
        paragraphMenuLanguages(
            roomLanguage: "es",
            recent: ["de", "es", "ja", "fr"],
            reachable: ["de", "es", "fr"]),
        ["es", "de", "fr"]);
    expect(
        paragraphMenuLanguages(
            recent: ["a", "b", "c"], reachable: ["a", "b", "c"], limit: 2),
        ["a", "b"]);
  });
}
