import 'package:flutter/material.dart';

/// Vommet issue 611: the words of an in-chat search, highlighted in the
/// room's own timeline (and in the list of matches), and the match the
/// search is on, outlined. Placed above the room's timeline only, so a thread
/// panel and other rooms stay plain.
class SearchHighlightScope extends InheritedWidget {
  const SearchHighlightScope({
    required this.words,
    this.currentEventId,
    required super.child,
    super.key,
  });

  /// Lowercased words to highlight; empty = nothing highlighted.
  final List<String> words;

  /// The match the search bar's "3 of 17" is on.
  final String? currentEventId;

  static SearchHighlightScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SearchHighlightScope>();

  /// The words to highlight under [context]; empty when not searching.
  static List<String> wordsOf(BuildContext context) =>
      maybeOf(context)?.words ?? const [];

  static bool isCurrent(BuildContext context, String eventId) =>
      maybeOf(context)?.currentEventId == eventId;

  @override
  bool updateShouldNotify(SearchHighlightScope oldWidget) =>
      currentEventId != oldWidget.currentEventId ||
      !_sameWords(words, oldWidget.words);

  static bool _sameWords(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// The words of a search query worth highlighting: filters such as
  /// `from:@a:b` or `has:image` are left out, as is case.
  static List<String> wordsOfQuery(String query) => [
        for (final w in query.split(RegExp(r'\s+')))
          if (w.isNotEmpty && !_filter.hasMatch(w)) w.toLowerCase()
      ];

  static final _filter = RegExp(r'^(from|has|type):', caseSensitive: false);

  /// How a matched word looks: the mockup's yellow on a dark theme, a yellow
  /// marker behind the text on a light one (yellow text wouldn't read there).
  static TextStyle styleOf(BuildContext context) {
    const yellow = Color(0xFFF5D76E);
    return Theme.of(context).brightness == Brightness.dark
        ? const TextStyle(color: yellow, fontWeight: FontWeight.w700)
        : const TextStyle(
            backgroundColor: yellow,
            color: Colors.black,
            fontWeight: FontWeight.w700);
  }

  /// Where [words] occur in [text], case-insensitively, as sorted
  /// non-overlapping (start, end) ranges.
  static List<(int, int)> matches(String text, List<String> words) {
    if (words.isEmpty || text.isEmpty) return const [];
    final lower = text.toLowerCase();
    // toLowerCase can change a string's length (a few non-Latin letters);
    // offsets would then be off, so don't highlight such text at all.
    if (lower.length != text.length) return const [];
    final ranges = <(int, int)>[];
    for (final word in words) {
      if (word.isEmpty) continue;
      var from = 0;
      while (true) {
        final at = lower.indexOf(word, from);
        if (at < 0) break;
        ranges.add((at, at + word.length));
        from = at + word.length;
      }
    }
    if (ranges.isEmpty) return const [];
    ranges.sort((a, b) => a.$1.compareTo(b.$1));
    final merged = <(int, int)>[ranges.first];
    for (final r in ranges.skip(1)) {
      final last = merged.last;
      if (r.$1 <= last.$2) {
        if (r.$2 > last.$2) merged[merged.length - 1] = (last.$1, r.$2);
      } else {
        merged.add(r);
      }
    }
    return merged;
  }

  /// [text] as spans with [words] in [highlight]; one plain span when
  /// nothing matches.
  static List<InlineSpan> textSpans(
      String text, List<String> words, TextStyle highlight,
      {TextStyle? style}) {
    final ranges = matches(text, words);
    if (ranges.isEmpty) return [TextSpan(text: text, style: style)];
    final marked = style?.merge(highlight) ?? highlight;
    final spans = <InlineSpan>[];
    var last = 0;
    for (final (start, end) in ranges) {
      if (start > last) {
        spans.add(TextSpan(text: text.substring(last, start), style: style));
      }
      spans.add(TextSpan(text: text.substring(start, end), style: marked));
      last = end;
    }
    if (last < text.length) {
      spans.add(TextSpan(text: text.substring(last), style: style));
    }
    return spans;
  }

  /// [spans] with [words] highlighted in their plain text. Links and other
  /// tappable or custom spans are kept as they are.
  static List<InlineSpan> highlightSpans(
      List<InlineSpan> spans, List<String> words, TextStyle highlight) {
    if (words.isEmpty) return spans;
    return [
      for (final span in spans)
        if (span.runtimeType == TextSpan &&
            (span as TextSpan).recognizer == null &&
            span.children == null &&
            span.text != null)
          ...textSpans(span.text!, words, highlight, style: span.style)
        else
          span
    ];
  }
}
