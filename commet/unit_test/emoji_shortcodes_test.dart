import 'package:commet/utils/emoji/emoji_shortcodes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/src/utils/markdown.dart' as mx_markdown;

// Vommet issue 483: typed :shortcode: becomes its emoji on send.
void main() {
  final emoji = EmojiShortcodes.buildMap({
    "1F62D": ["loudly_crying_face", "sob"],
    "1F92F": "exploding_head",
    "2764": "heart",
    "1F44D": ["+1", "thumbsup"],
  }, emojiByCodepoint: {
    "2764": "❤️",
  });

  String replace(String text, {Set<String> custom = const {}}) =>
      EmojiShortcodes.replace(
          text, (code) => custom.contains(code) ? null : emoji[code]);

  test('every alias maps to the emoji', () {
    expect(emoji["sob"], "😭");
    expect(emoji["loudly_crying_face"], "😭");
    expect(emoji["+1"], "👍");
    // The fully qualified emoji from the packs wins over the bare codepoint.
    expect(emoji["heart"], "❤️");
  });

  test('replaces standard shortcodes, also inside words', () {
    expect(replace("so sad :sob:"), "so sad 😭");
    expect(replace("abso:exploding_head:lutely"), "abso🤯lutely");
    expect(replace(":sob::sob:"), "😭😭");
    expect(replace(":+1: ok"), "👍 ok");
  });

  test('leaves unknown shortcodes and retries from the closing colon', () {
    expect(replace("at 12:30:45"), "at 12:30:45");
    expect(replace("a:nope:sob:"), "a:nope😭");
    expect(replace(":nope:"), ":nope:");
  });

  test('custom emoji win over standard ones with the same shortcode', () {
    expect(replace(":sob: :heart:", custom: {"sob"}), ":sob: ❤️");
  });

  test('skips escapes, code and URLs', () {
    expect(replace(r"\:sob: :sob:"), r"\:sob: 😭");
    expect(replace("`:sob:` :sob:"), "`:sob:` 😭");
    expect(replace("```\n:sob:\n```\n:sob:"), "```\n:sob:\n```\n😭");
    expect(replace("https://example.com/:sob:/x :sob:"),
        "https://example.com/:sob:/x 😭");
    expect(
        replace("<https://example.com/:sob:>"), "<https://example.com/:sob:>");
  });

  test('custom emoji are replaced inside words by the markdown', () {
    final html = mx_markdown.markdown("abso:party:lutely",
        getEmotePacks: () => {
              "pack": {"party": "mxc://example.com/party"}
            });
    expect(html, contains('abso<img data-mx-emoticon'));
    expect(html, contains('mxc://example.com/party'));
    expect(html, contains('>lutely'));
  });
}
