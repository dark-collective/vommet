// Vommet: translating what you write paragraph by paragraph, on send. Pure
// Dart (no Flutter), so it's unit-tested on its own; the composer state is
// in `ui/molecules/composer_translation.dart`.
//
// A paragraph is one line of the draft: the text between two newlines
// (Shift+Enter on a desktop, the keyboard's return key on a phone). Each
// paragraph has an optional target language. Blank lines are never
// translated; they keep their target so the next line typed there inherits
// it.

/// The target of a paragraph you said not to translate ("Don't translate"),
/// even in a room whose paragraphs default to the room's language.
const String keepAsWritten = "-";

/// [draft] cut into paragraphs (see the top of this file).
List<String> draftParagraphs(String draft) => draft.split("\n");

/// The paragraph [offset] (a caret position in [draft]) is in.
int paragraphAt(String draft, int offset) {
  final end = offset.clamp(0, draft.length);
  var line = 0;
  for (var i = 0; i < end; i++) {
    if (draft.codeUnitAt(i) == 10) line++;
  }
  return line;
}

/// The offsets of each paragraph of [draft] (newlines not included).
List<({int start, int end})> paragraphRanges(String draft) {
  final result = <({int start, int end})>[];
  var start = 0;
  for (final line in draftParagraphs(draft)) {
    result.add((start: start, end: start + line.length));
    start += line.length + 1;
  }
  return result;
}

/// The targets of [newLines] after an edit turned [oldLines] (with
/// [oldTargets]) into them. Unchanged paragraphs keep theirs; an edited one
/// keeps the target of the paragraph it was; a new paragraph inherits the
/// target of the one above it (null = none set: the room's default).
List<String?> carryTargets(
    List<String> oldLines, List<String?> oldTargets, List<String> newLines) {
  String? oldTarget(int i) => i < oldTargets.length ? oldTargets[i] : null;
  final o = oldLines.length;
  final n = newLines.length;
  var prefix = 0;
  while (prefix < o && prefix < n && oldLines[prefix] == newLines[prefix]) {
    prefix++;
  }
  var suffix = 0;
  while (suffix < o - prefix &&
      suffix < n - prefix &&
      oldLines[o - 1 - suffix] == newLines[n - 1 - suffix]) {
    suffix++;
  }
  final result = List<String?>.filled(n, null);
  for (var i = 0; i < prefix; i++) {
    result[i] = oldTarget(i);
  }
  final oldMiddle = o - prefix - suffix;
  final newMiddle = n - prefix - suffix;
  for (var k = 0; k < newMiddle; k++) {
    final i = prefix + k;
    if (oldMiddle == newMiddle) {
      result[i] = oldTarget(prefix + k);
    } else if (k == 0 && oldMiddle > 0) {
      result[i] = oldTarget(prefix);
    } else {
      result[i] = i > 0 ? result[i - 1] : null;
    }
  }
  for (var k = 0; k < suffix; k++) {
    result[n - suffix + k] = oldTarget(o - suffix + k);
  }
  return result;
}

/// The language each paragraph goes out in: its own target, else
/// [fallback] (the room's language in a room that translates what you
/// write); null = sent as written. Blank paragraphs and [keepAsWritten] are
/// never translated.
List<String?> resolveTargets(List<String> lines, List<String?> targets,
    {String? fallback}) {
  return [
    for (var i = 0; i < lines.length; i++)
      if (lines[i].trim().isEmpty)
        null
      else
        switch (i < targets.length ? targets[i] : null) {
          keepAsWritten => null,
          null => fallback,
          final code => code,
        }
  ];
}

/// What tapping 文A sets for a paragraph written in [from]: the usual
/// language, or null (= ask with "Translate into") when there isn't one or
/// the paragraph is already in it. Never a dead end saying "this is already
/// in English".
String? tapTarget({required String? usual, required String from}) =>
    usual == null || usual == from ? null : usual;

/// One run of consecutive paragraphs going out in the same language.
class SendBlock {
  const SendBlock(
      {required this.first, required this.number, required this.text, this.to});

  /// Index of its first paragraph in the draft.
  final int first;

  /// 1-based number of its first paragraph, counting non-blank ones (what
  /// error messages call it).
  final int number;

  /// Its paragraphs joined with newlines.
  final String text;

  /// The language to translate it into; null = as written.
  final String? to;

  @override
  String toString() => "SendBlock($first, #$number, $to, $text)";
}

/// [lines] grouped into runs with the same resolved target ([resolved],
/// from [resolveTargets]).
List<SendBlock> sendBlocks(List<String> lines, List<String?> resolved) {
  // numbers[i]: the number paragraph i has, or the next one gets (blank).
  final numbers = <int>[];
  var count = 0;
  for (final line in lines) {
    if (line.trim().isNotEmpty) count++;
    numbers.add(line.trim().isEmpty ? count + 1 : count);
  }
  final blocks = <SendBlock>[];
  var start = 0;
  for (var i = 1; i <= lines.length; i++) {
    if (i < lines.length && resolved[i] == resolved[start]) continue;
    blocks.add(SendBlock(
        first: start,
        number: numbers[start],
        text: lines.sublist(start, i).join("\n"),
        to: resolved[start]));
    start = i;
  }
  return blocks;
}

/// The message to send: each block's translation (by [SendBlock.first]) or
/// its text, joined with newlines.
String assembleSend(List<SendBlock> blocks, Map<int, String> translations) =>
    blocks.map((b) => translations[b.first] ?? b.text).join("\n");

/// The languages a message went out in, for "Sent in Spanish + German":
/// stored as "es+de" (Vommet: [SentTranslations] keeps one string).
String joinLanguages(Iterable<String> codes) => codes.toSet().join("+");

List<String> splitLanguages(String joined) =>
    joined.split("+").where((c) => c.isNotEmpty).toList();

/// The languages to list first in a paragraph's menu: the room's language,
/// then recent picks, among those [reachable]; at most [limit].
List<String> paragraphMenuLanguages(
    {String? roomLanguage,
    required List<String> recent,
    required List<String> reachable,
    int limit = 5}) {
  final result = <String>[];
  for (final c in [if (roomLanguage != null) roomLanguage, ...recent]) {
    if (reachable.contains(c) && !result.contains(c)) result.add(c);
  }
  return result.take(limit).toList();
}
