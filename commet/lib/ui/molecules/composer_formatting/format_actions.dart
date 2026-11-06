import 'package:flutter/services.dart';

/// Formats the composer can apply to the selection. Each one writes plain
/// Markdown (plus Vommet's `__underline__` and `||spoiler||`), so a message
/// formatted with the buttons looks the same as one typed by hand.
enum ComposerFormat {
  bold,
  italic,
  underline,
  strike,
  spoiler,
  code,
  quote,
  link,
}

const _markers = {
  ComposerFormat.bold: '**',
  ComposerFormat.italic: '*',
  ComposerFormat.underline: '__',
  ComposerFormat.strike: '~~',
  ComposerFormat.spoiler: '||',
  ComposerFormat.code: '`',
};

final _url = RegExp(r'^(https?://|matrix:)\S+$');

bool looksLikeUrl(String text) => _url.hasMatch(text.trim());

/// Applies [format] to the selection in [value], or removes it when the
/// selection already has it. A collapsed cursor gets an empty pair of
/// markers with the cursor between them. Link is handled by [insertLink].
TextEditingValue toggleFormat(TextEditingValue value, ComposerFormat format) {
  if (!value.selection.isValid) return value;
  switch (format) {
    case ComposerFormat.quote:
      return _toggleQuote(value);
    case ComposerFormat.code:
      if (_selectedText(value).contains('\n')) return _toggleCodeBlock(value);
      return _toggleInline(value, _markers[format]!);
    case ComposerFormat.link:
      return value;
    default:
      return _toggleInline(value, _markers[format]!);
  }
}

/// Whether the selection (or the cursor) already has [format].
bool isFormatActive(TextEditingValue value, ComposerFormat format) {
  if (!value.selection.isValid) return false;
  if (format == ComposerFormat.quote) {
    var (start, end) = _lineRange(value.text, value.selection);
    var lines = value.text.substring(start, end).split('\n');
    return lines.where((l) => l.trim().isNotEmpty).every(_isQuoted) &&
        lines.any((l) => l.trim().isNotEmpty);
  }
  var marker = _markers[format];
  if (marker == null) return false;
  var (start, end) = _trimmed(value.text, value.selection);
  return _wrappedOutside(value.text, start, end, marker) ||
      _wrappedInside(value.text, start, end, marker);
}

/// Replaces the selection with a Markdown link.
TextEditingValue insertLink(TextEditingValue value, String text, String url) {
  var label = text.trim().isEmpty ? url.trim() : text.trim();
  label = label.replaceAll('[', r'\[').replaceAll(']', r'\]');
  var target = url.trim().replaceAll(' ', '%20').replaceAll(')', '%29');
  var link = '[$label]($target)';
  var sel = value.selection.isValid
      ? value.selection
      : TextSelection.collapsed(offset: value.text.length);
  var newText = value.text.replaceRange(sel.start, sel.end, link);
  return TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: sel.start + link.length));
}

/// When [after] is [before] with its non-empty selection replaced by a
/// pasted URL, returns the selection turned into a link to that URL.
TextEditingValue? linkFromPaste(
    TextEditingValue before, TextEditingValue after) {
  var sel = before.selection;
  if (!sel.isValid || sel.isCollapsed) return null;
  var selected = before.text.substring(sel.start, sel.end);
  if (selected.trim().isEmpty || looksLikeUrl(selected)) return null;
  var prefix = before.text.substring(0, sel.start);
  var suffix = before.text.substring(sel.end);
  if (!after.text.startsWith(prefix) || !after.text.endsWith(suffix)) {
    return null;
  }
  if (after.text.length < prefix.length + suffix.length) return null;
  var pasted =
      after.text.substring(prefix.length, after.text.length - suffix.length);
  if (pasted.contains(RegExp(r'\s')) || !looksLikeUrl(pasted)) return null;
  if (after.selection.baseOffset != prefix.length + pasted.length) return null;
  return insertLink(
      TextEditingValue(text: before.text, selection: sel), selected, pasted);
}

String _selectedText(TextEditingValue v) =>
    v.text.substring(v.selection.start, v.selection.end);

bool _isQuoted(String line) => line.startsWith('>');

/// Selection with surrounding whitespace dropped, as Discord does when a
/// double-click picks up the space after a word.
(int, int) _trimmed(String text, TextSelection sel) {
  var start = sel.start;
  var end = sel.end;
  while (start < end && _isSpace(text[start])) {
    start++;
  }
  while (end > start && _isSpace(text[end - 1])) {
    end--;
  }
  if (start == end) return (sel.start, sel.start);
  return (start, end);
}

bool _isSpace(String c) => c == ' ' || c == '\t' || c == '\n';

int _runBefore(String text, int index, String char) {
  var n = 0;
  while (index - n - 1 >= 0 && text[index - n - 1] == char) {
    n++;
  }
  return n;
}

int _runAfter(String text, int index, String char) {
  var n = 0;
  while (index + n < text.length && text[index + n] == char) {
    n++;
  }
  return n;
}

/// `*` and `**` share a character, so they're told apart by run length:
/// italic is a run of 1 or 3, bold a run of 2 or more.
bool _runMatches(int run, String marker) {
  if (marker == '*') return run == 1 || run == 3;
  if (marker == '**') return run >= 2;
  return run >= marker.length;
}

bool _wrappedOutside(String text, int start, int end, String marker) {
  var c = marker[0];
  if (marker.split('').any((m) => m != c)) return false;
  return _runMatches(_runBefore(text, start, c), marker) &&
      _runMatches(_runAfter(text, end, c), marker);
}

bool _wrappedInside(String text, int start, int end, String marker) {
  if (end - start < marker.length * 2 + 1) return false;
  var c = marker[0];
  return _runMatches(_runAfter(text, start, c), marker) &&
      _runMatches(_runBefore(text, end, c), marker);
}

TextEditingValue _toggleInline(TextEditingValue value, String marker) {
  var text = value.text;
  var m = marker.length;

  if (value.selection.isCollapsed) {
    var at = value.selection.baseOffset;
    // Pressing again right after inserting an empty pair takes it back out.
    if (at >= m &&
        at + m <= text.length &&
        text.substring(at - m, at) == marker &&
        text.substring(at, at + m) == marker) {
      return TextEditingValue(
          text: text.replaceRange(at - m, at + m, ''),
          selection: TextSelection.collapsed(offset: at - m));
    }
    return TextEditingValue(
        text: text.replaceRange(at, at, marker + marker),
        selection: TextSelection.collapsed(offset: at + m));
  }

  var (start, end) = _trimmed(text, value.selection);
  if (start == end) {
    return _toggleInline(
        value.copyWith(selection: TextSelection.collapsed(offset: start)),
        marker);
  }

  if (_wrappedOutside(text, start, end, marker)) {
    var newText = text.replaceRange(end, end + m, '');
    newText = newText.replaceRange(start - m, start, '');
    return TextEditingValue(
        text: newText,
        selection: TextSelection(baseOffset: start - m, extentOffset: end - m));
  }

  if (_wrappedInside(text, start, end, marker)) {
    var newText = text.replaceRange(end - m, end, '');
    newText = newText.replaceRange(start, start + m, '');
    return TextEditingValue(
        text: newText,
        selection: TextSelection(baseOffset: start, extentOffset: end - 2 * m));
  }

  var newText = text.replaceRange(end, end, marker);
  newText = newText.replaceRange(start, start, marker);
  return TextEditingValue(
      text: newText,
      selection: TextSelection(baseOffset: start + m, extentOffset: end + m));
}

(int, int) _lineRange(String text, TextSelection sel) {
  var start = sel.start == 0 ? 0 : text.lastIndexOf('\n', sel.start - 1) + 1;
  var end = text.indexOf('\n', sel.end);
  if (end == -1) end = text.length;
  return (start, end);
}

TextEditingValue _toggleQuote(TextEditingValue value) {
  var text = value.text;
  var (start, end) = _lineRange(text, value.selection);
  var lines = text.substring(start, end).split('\n');
  var content = lines.where((l) => l.trim().isNotEmpty);
  var unquote = content.isNotEmpty && content.every(_isQuoted);

  var newLines = lines.map((l) {
    if (unquote) {
      return l.startsWith('> ') ? l.substring(2) : l.replaceFirst('>', '');
    }
    return l.trim().isEmpty && lines.length > 1 ? l : '> $l';
  }).toList();
  var block = newLines.join('\n');
  var newText = text.replaceRange(start, end, block);

  if (value.selection.isCollapsed) {
    var delta = newLines.first.length - lines.first.length;
    var at =
        (value.selection.baseOffset + delta).clamp(start, start + block.length);
    return TextEditingValue(
        text: newText, selection: TextSelection.collapsed(offset: at));
  }
  return TextEditingValue(
      text: newText,
      selection:
          TextSelection(baseOffset: start, extentOffset: start + block.length));
}

TextEditingValue _toggleCodeBlock(TextEditingValue value) {
  var text = value.text;
  var (start, end) = _lineRange(text, value.selection);
  var block = text.substring(start, end);
  var lines = block.split('\n');
  if (lines.length >= 2 &&
      lines.first.trim().startsWith('```') &&
      lines.last.trim() == '```') {
    var inner = lines.sublist(1, lines.length - 1).join('\n');
    return TextEditingValue(
        text: text.replaceRange(start, end, inner),
        selection: TextSelection(
            baseOffset: start, extentOffset: start + inner.length));
  }
  var fenced = '```\n$block\n```';
  return TextEditingValue(
      text: text.replaceRange(start, end, fenced),
      selection: TextSelection(
          baseOffset: start + 4, extentOffset: start + 4 + block.length));
}
