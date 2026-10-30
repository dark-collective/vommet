// Vommet (chat navigation): the word-level changes between two versions of
// an edited message, for the edit history's "Show changes".

enum WordDiffKind { same, added, removed }

class WordDiffPart {
  const WordDiffPart(this.text, this.kind);
  final String text;
  final WordDiffKind kind;

  @override
  bool operator ==(Object other) =>
      other is WordDiffPart && other.text == text && other.kind == kind;

  @override
  int get hashCode => Object.hash(text, kind);

  @override
  String toString() => "${kind.name}(\"$text\")";
}

class WordDiff {
  /// Past this many words on either side, the whole text counts as replaced
  /// (the comparison grows with the product of the two lengths).
  static const maxWords = 1500;

  static final _tokens = RegExp(r"\s+|\S+");

  /// The parts of [after] and [before] in reading order: unchanged words,
  /// words only [before] had ([WordDiffKind.removed]) and words only [after]
  /// has ([WordDiffKind.added]). Whitespace stays with the words around it.
  static List<WordDiffPart> diff(String before, String after) {
    final a = _tokens.allMatches(before).map((m) => m.group(0)!).toList();
    final b = _tokens.allMatches(after).map((m) => m.group(0)!).toList();
    if (a.length > maxWords || b.length > maxWords) {
      return _merge([
        if (before.isNotEmpty) WordDiffPart(before, WordDiffKind.removed),
        if (after.isNotEmpty) WordDiffPart(after, WordDiffKind.added),
      ]);
    }

    // Longest common subsequence, filled from the end.
    final lcs =
        List.generate(a.length + 1, (_) => List.filled(b.length + 1, 0));
    for (var i = a.length - 1; i >= 0; i--) {
      for (var j = b.length - 1; j >= 0; j--) {
        lcs[i][j] = a[i] == b[j]
            ? lcs[i + 1][j + 1] + 1
            : (lcs[i + 1][j] >= lcs[i][j + 1] ? lcs[i + 1][j] : lcs[i][j + 1]);
      }
    }

    final parts = <WordDiffPart>[];
    var i = 0, j = 0;
    while (i < a.length && j < b.length) {
      if (a[i] == b[j]) {
        parts.add(WordDiffPart(a[i], WordDiffKind.same));
        i++;
        j++;
      } else if (lcs[i + 1][j] >= lcs[i][j + 1]) {
        parts.add(WordDiffPart(a[i++], WordDiffKind.removed));
      } else {
        parts.add(WordDiffPart(b[j++], WordDiffKind.added));
      }
    }
    while (i < a.length) {
      parts.add(WordDiffPart(a[i++], WordDiffKind.removed));
    }
    while (j < b.length) {
      parts.add(WordDiffPart(b[j++], WordDiffKind.added));
    }
    return _merge(parts);
  }

  /// Joins neighbors of the same kind, and lets a lone space between two
  /// changes of one kind join them ("old words" rather than "old", " ", "words").
  static List<WordDiffPart> _merge(List<WordDiffPart> parts) {
    final out = <WordDiffPart>[];
    for (var k = 0; k < parts.length; k++) {
      var part = parts[k];
      final isSpace = part.text.trim().isEmpty;
      if (isSpace &&
          part.kind == WordDiffKind.same &&
          out.isNotEmpty &&
          k + 1 < parts.length &&
          out.last.kind != WordDiffKind.same &&
          parts[k + 1].kind == out.last.kind) {
        part = WordDiffPart(part.text, out.last.kind);
      }
      if (out.isNotEmpty && out.last.kind == part.kind) {
        out[out.length - 1] =
            WordDiffPart(out.last.text + part.text, part.kind);
      } else {
        out.add(part);
      }
    }
    return out;
  }
}
