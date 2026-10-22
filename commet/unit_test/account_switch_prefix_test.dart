import 'package:commet/client/components/account_switch_prefix/account_switch_prefix.dart';
import 'package:test/test.dart';

void main() {
  group("normalize", () {
    test("keeps a trailing space", () {
      expect(AccountPrefixText.normalize("e "), "e ");
    });

    test("drops leading whitespace", () {
      expect(AccountPrefixText.normalize("  e "), "e ");
    });

    test("clears empty and whitespace-only prefixes", () {
      expect(AccountPrefixText.normalize(null), isNull);
      expect(AccountPrefixText.normalize(""), isNull);
      expect(AccountPrefixText.normalize("   "), isNull);
    });
  });

  group("matches", () {
    test("prefix with a space needs the space", () {
      expect(AccountPrefixText.matches("elderberries", "e "), isFalse);
      expect(AccountPrefixText.matches("e elderberries", "e "), isTrue);
    });

    test("empty prefix never matches", () {
      expect(AccountPrefixText.matches("hello", ""), isFalse);
    });
  });

  group("remove", () {
    test("leaves text without the prefix alone", () {
      expect(AccountPrefixText.remove("elderberries", "e "), "elderberries");
    });

    test("strips the prefix and the whitespace after it", () {
      expect(AccountPrefixText.remove("e  elderberries", "e "), "elderberries");
      expect(AccountPrefixText.remove("!alt hi", "!alt"), "hi");
    });
  });

  group("possiblyMatches", () {
    test("text that is the start of the prefix", () {
      expect(AccountPrefixText.possiblyMatches("e", "e "), isTrue);
      expect(AccountPrefixText.possiblyMatches("", "e "), isTrue);
    });

    test("text past the prefix must start with it", () {
      expect(AccountPrefixText.possiblyMatches("el", "e "), isFalse);
      expect(AccountPrefixText.possiblyMatches("e hi", "e "), isTrue);
    });

    test("empty prefix", () {
      expect(AccountPrefixText.possiblyMatches("", ""), isFalse);
    });
  });
}
