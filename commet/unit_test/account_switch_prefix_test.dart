import 'package:commet/client/components/account_switch_prefix/account_switch_prefix.dart';
import 'package:test/test.dart';

const prefix = SendAsPattern(before: "e ");
const suffix = SendAsPattern(after: "-p");
const wrapper = SendAsPattern(before: "(", after: ")");

void main() {
  group("normalize", () {
    test("keeps the space next to the message", () {
      expect(SendAsPattern.normalize("e ", ""), prefix);
      expect(
          SendAsPattern.normalize("", " p"), const SendAsPattern(after: " p"));
    });

    test("drops the space on the far side", () {
      expect(SendAsPattern.normalize("  e ", ""), prefix);
      expect(SendAsPattern.normalize("", "-p  "), suffix);
    });

    test("clears empty and whitespace-only patterns", () {
      expect(SendAsPattern.normalize("", ""), isNull);
      expect(SendAsPattern.normalize("   ", " "), isNull);
    });
  });

  group("messageIn", () {
    test("prefix with a space needs the space", () {
      expect(prefix.messageIn("elderberries"), isNull);
      expect(prefix.messageIn("e  elderberries"), "elderberries");
      expect(const SendAsPattern(before: "!alt").messageIn("!alt hi"), "hi");
    });

    test("suffix", () {
      expect(suffix.messageIn("hello-p"), "hello");
      expect(suffix.messageIn("hello - p"), isNull);
      expect(const SendAsPattern(after: "- p").messageIn("hello - p"), "hello");
      expect(suffix.messageIn("hello"), isNull);
    });

    test("wrapper", () {
      expect(wrapper.messageIn("( on my way )"), "on my way");
      expect(wrapper.messageIn("(on my way"), isNull);
      expect(wrapper.messageIn("on my way)"), isNull);
    });

    test("keeps formatting and lines inside", () {
      expect(wrapper.messageIn("(**hi**\nthere)"), "**hi**\nthere");
    });

    test("nothing inside is no match", () {
      expect(wrapper.messageIn("()"), isNull);
      expect(wrapper.messageIn("(  )"), isNull);
      expect(wrapper.messageIn(")"), isNull);
      expect(prefix.messageIn("e "), isNull);
      expect(suffix.messageIn(" -p"), isNull);
    });

    test("empty pattern never matches", () {
      expect(const SendAsPattern().messageIn("hello"), isNull);
    });
  });

  group("possiblyMatches", () {
    test("text that is the start of the prefix", () {
      expect(prefix.possiblyMatches("e"), isTrue);
      expect(prefix.possiblyMatches(""), isTrue);
    });

    test("text past the prefix must start with it", () {
      expect(prefix.possiblyMatches("el"), isFalse);
      expect(prefix.possiblyMatches("e hi"), isTrue);
    });

    test("a suffix can't be told apart yet", () {
      expect(suffix.possiblyMatches("hello-"), isFalse);
      expect(const SendAsPattern().possiblyMatches(""), isFalse);
    });
  });

  group("beats", () {
    test("longer wins", () {
      expect(
          const SendAsPattern(before: "pp:")
              .beats(const SendAsPattern(before: "p:")),
          isTrue);
      expect(
          const SendAsPattern(before: "p:")
              .beats(const SendAsPattern(before: "pp:")),
          isFalse);
    });

    test("on a tie, a before part wins", () {
      expect(wrapper.beats(suffix), isTrue);
      expect(suffix.beats(wrapper), isFalse);
      expect(wrapper.beats(wrapper), isFalse);
    });
  });

  group("storage", () {
    test("reads a FluffyChat prefix", () {
      expect(SendAsPatternStorage.read({"prefix": "p:"}),
          [const SendAsPattern(before: "p:")]);
      expect(SendAsPatternStorage.read(null), isEmpty);
    });

    test("round-trips patterns and keeps the first prefix for FluffyChat", () {
      final content = SendAsPatternStorage.write({
        "bundles": {"a": 1},
        "prefix": "old"
      }, [
        suffix,
        wrapper,
        prefix,
        const SendAsPattern(before: "p.")
      ]);
      expect(content["prefix"], "e ");
      expect(content["bundles"], {"a": 1});
      expect(SendAsPatternStorage.read(content),
          [suffix, wrapper, prefix, const SendAsPattern(before: "p.")]);
    });

    test("no prefix-only pattern clears the FluffyChat prefix", () {
      final content = SendAsPatternStorage.write({"prefix": "old"}, [wrapper]);
      expect(content.containsKey("prefix"), isFalse);
      expect(SendAsPatternStorage.read(content), [wrapper]);
    });

    test("clearing removes both keys", () {
      final content = SendAsPatternStorage.write(
          {"prefix": "p:", SendAsPatternStorage.patternsKey: []}, []);
      expect(content, isEmpty);
    });

    test("a prefix changed elsewhere is still used", () {
      final content = SendAsPatternStorage.write({}, [wrapper]);
      content["prefix"] = "x:";
      expect(SendAsPatternStorage.read(content),
          [const SendAsPattern(before: "x:"), wrapper]);
    });

    test("drops repeats and bad entries", () {
      expect(
          SendAsPatternStorage.read({
            SendAsPatternStorage.patternsKey: [
              wrapper.toJson(),
              wrapper.toJson(),
              "junk",
              {"before": 3},
            ]
          }),
          [wrapper]);
    });
  });
}
