import 'package:commet/client/components/url_preview/outgoing_url_preview.dart';
import 'package:commet/utils/links/tracking_parameters_cleaner.dart';

/// Vommet: "Clean links I send" removes tracking parts (utm_source, fbclid,
/// YouTube's si=, ...) from links in a message before it is sent, using the
/// ClearURLs rules the app already ships for opening links.
///
/// Unlike [UrlParameterRule.process], which rebuilds the whole query, this
/// only cuts the matching `key=value` pairs out of the text: everything else
/// in the link (order, encoding, repeated keys) stays exactly as typed, and
/// a link with nothing to remove is left untouched. Links inside code spans
/// and code blocks are never changed.
class SentLinkCleaner {
  static final RegExp _url = RegExp(r'''https?://[^\s<>"'`]+''');
  static final RegExp _trailing = RegExp(r'[.,;:!?)\]}>*_~]+$');
  static final RegExp _code = RegExp(r'```[\s\S]*?(?:```|$)|`[^`\n]*`');

  /// Cleans every link in [message] with the loaded ClearURLs rules.
  static Future<String> cleanMessage(String message) async {
    if (!message.contains("http")) return message;
    if (UrlTrackingParametersCleaner.parameterRules.isEmpty) {
      await UrlTrackingParametersCleaner.init();
    }
    return clean(
        message, UrlTrackingParametersCleaner.parameterRules.values.toList());
  }

  /// [previews] with their links cleaned the same way, so a preview made
  /// while typing still goes with the cleaned link it describes.
  static Future<List<OutgoingUrlPreview>?> cleanPreviews(
      List<OutgoingUrlPreview>? previews) async {
    if (previews == null) return null;
    final rules = UrlTrackingParametersCleaner.parameterRules.values.toList();
    return previews.map((p) {
      final link = p.matchedUrl.toString();
      final cleaned = cleanLink(link, rules);
      if (cleaned == link) return p;
      final uri = Uri.tryParse(cleaned);
      if (uri == null) return p;
      return OutgoingUrlPreview(
          matchedUrl: uri,
          title: p.title,
          description: p.description,
          siteName: p.siteName,
          image: p.image);
    }).toList();
  }

  /// Cleans every link in [message] with [rules].
  static String clean(String message, List<UrlParameterRule> rules) {
    final result = StringBuffer();
    var last = 0;
    for (final block in _code.allMatches(message)) {
      result.write(_cleanText(message.substring(last, block.start), rules));
      result.write(block.group(0));
      last = block.end;
    }
    result.write(_cleanText(message.substring(last), rules));
    return result.toString();
  }

  static String _cleanText(String text, List<UrlParameterRule> rules) {
    return text.replaceAllMapped(_url, (match) {
      var link = match.group(0)!;
      final tail = _trailing.firstMatch(link)?.group(0) ?? "";
      link = link.substring(0, link.length - tail.length);
      return cleanLink(link, rules) + tail;
    });
  }

  /// [link] without its tracking parameters, or [link] itself when no rule
  /// removes anything.
  static String cleanLink(String link, List<UrlParameterRule> rules) {
    var result = link;
    for (final rule in rules) {
      if (rule.completeProvider) continue;
      try {
        if (!RegExp(rule.urlPattern).hasMatch(result)) continue;
        if (rule.exceptions?.any((e) => RegExp(e).hasMatch(result)) == true) {
          continue;
        }
        for (final raw in rule.rawRules ?? const <String>[]) {
          result = result.replaceAll(RegExp(raw), "");
        }
        final names = rule.rules;
        if (names != null && names.isNotEmpty) {
          result = _dropParameters(result, names);
        }
      } catch (_) {
        // A rule the Dart regex engine can't read removes nothing.
      }
    }
    return result;
  }

  static String _dropParameters(String link, List<String> names) {
    final queryStart = link.indexOf("?");
    if (queryStart == -1) return link;
    final fragmentStart = link.indexOf("#", queryStart);
    final queryEnd = fragmentStart == -1 ? link.length : fragmentStart;
    final query = link.substring(queryStart + 1, queryEnd);
    if (query.isEmpty) return link;

    final patterns = names.map((n) => RegExp("^(?:$n)\$")).toList();
    final pairs = query.split("&");
    final kept = pairs.where((pair) {
      final rawKey = pair.split("=").first;
      String key;
      try {
        key = Uri.decodeQueryComponent(rawKey);
      } catch (_) {
        key = rawKey;
      }
      return !patterns.any((p) => p.hasMatch(key));
    }).toList();
    if (kept.length == pairs.length) return link;

    final rest = link.substring(queryEnd);
    final base = link.substring(0, queryStart);
    if (kept.every((p) => p.isEmpty)) return base + rest;
    return "$base?${kept.join("&")}$rest";
  }
}
