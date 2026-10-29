import 'package:commet/utils/emoji/unicode_emoji.dart';

/// Vommet: turns typed `:shortcode:` into its standard emoji when a message
/// is sent, like Discord, also inside words (`abso:exploding_head:lutely`).
/// Custom emoji are left for the SDK markdown, which already replaces them,
/// and win when a custom and a standard shortcode clash. Code spans, fenced
/// code blocks, URLs and `\:escaped:` shortcodes are left alone.
class EmojiShortcodes {
  static Map<String, String>? _emojiByShortcode;

  static final _fence = RegExp(r'^ {0,3}(`{3,}|~{3,})');
  static final _codeSpan = RegExp(r'(`+)[\s\S]*?\1');
  static final _url = RegExp(r'<[^<>\s]+>|\b[a-zA-Z][a-zA-Z0-9+.-]*://\S+');
  static final _shortcode = RegExp(r':([\w+-]+):');

  /// Every shortcode (all aliases, e.g. both `loudly_crying_face` and `sob`)
  /// mapped to its emoji.
  static Future<Map<String, String>> load() async {
    if (_emojiByShortcode != null) return _emojiByShortcode!;

    await UnicodeEmojis.loadShortcodeData();
    var packs = UnicodeEmojis.packs ?? await UnicodeEmojis.load();

    // The packs carry the fully qualified emoji (with U+FE0F where needed),
    // keyed the same way as the shortcode data.
    var emojiByCodepoint = <String, String>{};
    for (var pack in packs) {
      for (var emoji in pack.emoji) {
        emojiByCodepoint[UnicodeEmoticon.emojiToUnicode(emoji.slug)
            .toUpperCase()] = emoji.slug;
      }
    }

    _emojiByShortcode = buildMap(UnicodeEmojis.shortcodeData!,
        emojiByCodepoint: emojiByCodepoint);
    return _emojiByShortcode!;
  }

  /// Builds the shortcode map from the `shortcodes/en.json` data
  /// (codepoints → shortcode or list of shortcodes).
  static Map<String, String> buildMap(Map<String, dynamic> shortcodeData,
      {Map<String, String> emojiByCodepoint = const {}}) {
    var result = <String, String>{};
    for (var entry in shortcodeData.entries) {
      var emoji = emojiByCodepoint[entry.key] ??
          String.fromCharCodes(
              entry.key.split('-').map((e) => int.parse(e, radix: 16)));
      var codes = entry.value;
      for (var code in codes is List ? codes : [codes]) {
        if (code is String) result.putIfAbsent(code, () => emoji);
      }
    }
    return result;
  }

  /// [message] with the standard emoji shortcodes replaced.
  static Future<String> replaceInMessage(String message,
      {Map<String, Map<String, String>>? customPacks}) async {
    if (!message.contains(':')) return message;
    var emoji = await load();
    var custom = <String>{
      for (var pack in customPacks?.values ?? <Map<String, String>>[])
        ...pack.keys
    };
    return replace(
        message, (code) => custom.contains(code) ? null : emoji[code]);
  }

  /// [text] with every `:shortcode:` that [lookup] knows replaced.
  static String replace(String text, String? Function(String) lookup) {
    var lines = text.split('\n');
    String? fence;
    for (var i = 0; i < lines.length; i++) {
      var marker = _fence.firstMatch(lines[i])?.group(1);
      if (fence != null) {
        if (marker != null &&
            marker[0] == fence[0] &&
            marker.length >= fence.length &&
            lines[i].trim() == marker) {
          fence = null;
        }
        continue;
      }
      if (marker != null) {
        fence = marker;
        continue;
      }
      lines[i] = _replaceLine(lines[i], lookup);
    }
    return lines.join('\n');
  }

  static String _replaceLine(String line, String? Function(String) lookup) {
    // Leave code spans and URLs as they are.
    var skip = [
      ..._codeSpan.allMatches(line),
      ..._url.allMatches(line),
    ];
    bool skipped(int index) =>
        skip.any((m) => index >= m.start && index < m.end);

    var out = StringBuffer();
    var pos = 0;
    var search = 0;
    while (search < line.length) {
      var match = _shortcode.allMatches(line, search).firstOrNull;
      if (match == null) break;

      var replacement = (match.start > 0 && line[match.start - 1] == '\\') ||
              skipped(match.start) ||
              skipped(match.end - 1)
          ? null
          : lookup(match.group(1)!);

      if (replacement == null) {
        // The closing colon may open the next shortcode (`a:b:sob:`).
        search = match.end - 1;
        continue;
      }

      out.write(line.substring(pos, match.start));
      out.write(replacement);
      pos = match.end;
      search = match.end;
    }
    out.write(line.substring(pos));
    return out.toString();
  }
}
