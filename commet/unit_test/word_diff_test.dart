// Vommet (chat navigation): the edit history's "Show changes" marks words
// that were added or removed between two versions.
import 'package:commet/utils/word_diff.dart';
import 'package:flutter_test/flutter_test.dart';

String side(List<WordDiffPart> parts, WordDiffKind skipped) =>
    parts.where((p) => p.kind != skipped).map((p) => p.text).join();

void expectRebuilds(String before, String after) {
  final parts = WordDiff.diff(before, after);
  expect(side(parts, WordDiffKind.added), before);
  expect(side(parts, WordDiffKind.removed), after);
}

void main() {
  test("a replaced word shows as removed then added", () {
    expect(WordDiff.diff("the cat sat", "the dog sat"), const [
      WordDiffPart("the ", WordDiffKind.same),
      WordDiffPart("cat", WordDiffKind.removed),
      WordDiffPart("dog", WordDiffKind.added),
      WordDiffPart(" sat", WordDiffKind.same),
    ]);
  });

  test("unchanged text is one unchanged part", () {
    expect(WordDiff.diff("same words", "same words"),
        const [WordDiffPart("same words", WordDiffKind.same)]);
  });

  test("each side rebuilds its own version", () {
    expectRebuilds("hello world", "hello there world");
    expectRebuilds("see you at 5 tomorrow", "see you at 6 on Friday");
    expectRebuilds("", "new text");
    expectRebuilds("old text", "");
    expectRebuilds("line one\nline two", "line one\n\nline 2");
  });

  test("very long texts count as replaced whole", () {
    final before = List.filled(WordDiff.maxWords, "a").join(" ");
    final after = "$before b";
    expect(WordDiff.diff(before, after), [
      WordDiffPart(before, WordDiffKind.removed),
      WordDiffPart(after, WordDiffKind.added),
    ]);
  });
}
