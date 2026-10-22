// Vommet: which parts of a message are words to spellcheck, and drawing the
// wavy underline into the message box's text spans. Pure Dart, no engine.
import 'package:flutter/widgets.dart';

class SpellcheckText {
  static final RegExp _word =
      RegExp(r"[\p{L}\p{M}]+(?:['’][\p{L}\p{M}]+)*", unicode: true);

  /// Text that is never checked: code, links, addresses, Matrix ids and
  /// mentions, emoji shortcodes and /commands.
  static final RegExp _skip = RegExp(
      [
        r"```[\s\S]*?(?:```|(?![\s\S]))",
        r"`[^`\n]*`?",
        r"\[[^\]\n]*\]\([^)\n]*\)?",
        r"(?:https?://|www\.)\S+",
        r"\S*@\S+",
        r"[#!+][^\s:]+:\S+",
        r"\b\w[\w-]*(?:\.\w[\w-]*)+",
        r":[\w+-]+:?",
        r"^/\S+",
      ].join("|"),
      multiLine: true,
      unicode: true);

  static final RegExp _digitOrUnderscore = RegExp(r"[\d_]");

  /// The ranges of [text] that are words worth checking.
  static List<TextRange> words(String text) {
    final skipped = [
      for (final m in _skip.allMatches(text))
        TextRange(start: m.start, end: m.end)
    ];
    final result = <TextRange>[];
    var s = 0;
    for (final m in _word.allMatches(text)) {
      while (s < skipped.length && skipped[s].end <= m.start) {
        s++;
      }
      if (s < skipped.length && skipped[s].start < m.end) continue;

      final word = m.group(0)!;
      if (word.length < 2) continue;
      // Part of an identifier or a number, like "abc123" or "snake_case".
      if (m.start > 0 && _digitOrUnderscore.hasMatch(text[m.start - 1])) {
        continue;
      }
      if (m.end < text.length && _digitOrUnderscore.hasMatch(text[m.end])) {
        continue;
      }
      // Acronyms (LOL, HTTP) and camelCase names (iPhone, McDonald) are left alone.
      if (word == word.toUpperCase()) continue;
      if (word.substring(1) != word.substring(1).toLowerCase()) continue;

      result.add(TextRange(start: m.start, end: m.end));
    }
    return result;
  }

  /// [ranges] without the word the caret sits at the end of: it is still
  /// being typed.
  static List<TextRange> withoutWordBeingTyped(
      List<TextRange> ranges, TextSelection selection) {
    if (!selection.isValid || !selection.isCollapsed) return ranges;
    return ranges.where((r) => r.end != selection.baseOffset).toList();
  }

  /// [span] with [mark] applied to the characters in [ranges]. Inline widgets
  /// (pills, emoji) count as one character each, as they do in the editor.
  static TextSpan mark(TextSpan span, List<TextRange> ranges, TextStyle mark) {
    if (ranges.isEmpty) return span;
    return _Marker(ranges, mark).visit(span) as TextSpan;
  }
}

class _Marker {
  final List<TextRange> ranges;
  final TextStyle style;
  int offset = 0;

  _Marker(this.ranges, this.style);

  InlineSpan visit(InlineSpan span) {
    if (span is! TextSpan) {
      offset += 1;
      return span;
    }

    final text = span.text;
    List<InlineSpan>? parts;
    if (text != null && text.isNotEmpty) {
      if (span.style?.fontFamily != "code") parts = _split(text, offset);
      offset += text.length;
    }
    final children = span.children?.map(visit).toList();

    if (parts == null) {
      return _copy(span, text: text, children: children);
    }
    return _copy(span, text: null, children: [...parts, ...?children]);
  }

  /// [text] (starting at [start] in the message) cut at the marked ranges, or
  /// null when nothing in it is marked.
  List<InlineSpan>? _split(String text, int start) {
    final end = start + text.length;
    List<InlineSpan>? parts;
    var cursor = start;
    for (final r in ranges) {
      if (r.end <= start || r.start >= end) continue;
      parts ??= [];
      final from = r.start < start ? start : r.start;
      final to = r.end > end ? end : r.end;
      if (from > cursor) {
        parts.add(TextSpan(text: text.substring(cursor - start, from - start)));
      }
      parts.add(TextSpan(
          text: text.substring(from - start, to - start), style: style));
      cursor = to;
    }
    if (parts != null && cursor < end) {
      parts.add(TextSpan(text: text.substring(cursor - start)));
    }
    return parts;
  }

  static TextSpan _copy(TextSpan span,
      {required String? text, required List<InlineSpan>? children}) {
    return TextSpan(
      text: text,
      children: children,
      style: span.style,
      recognizer: span.recognizer,
      mouseCursor: span.mouseCursor,
      onEnter: span.onEnter,
      onExit: span.onExit,
      semanticsLabel: span.semanticsLabel,
      locale: span.locale,
      spellOut: span.spellOut,
    );
  }
}
