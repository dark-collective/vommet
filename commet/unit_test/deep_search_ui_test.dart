// Vommet (Deep Search, stage 2): the UI's pure helpers: snippets around
// the first match, "+N more here" groups, the results bar's steps, the
// strip's "99+" and the ✓ seen / last-opened marks.
import 'package:commet/ui/organisms/new_home/deep_search/deep_search_results.dart';
import 'package:commet/ui/organisms/new_home/deep_search/deep_search_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

const _minute = 60 * 1000;

DeepSearchResult _hit(String id,
        {String room = "!tea:example.org",
        String account = "acct-a",
        int ts = 0,
        DeepSearchSource source = DeepSearchSource.indexed}) =>
    DeepSearchResult(
        accountId: account,
        roomId: room,
        eventId: id,
        senderId: "@mira:example.org",
        ts: ts,
        source: source,
        content: const {"body": "oolong"});

void main() {
  group("deepSearchSnippet", () {
    test("short bodies stay whole", () {
      expect(
          deepSearchSnippet("green tea  please", ["tea"]), "green tea please");
    });

    test("reply fallbacks are left out", () {
      expect(
          deepSearchSnippet(
              "> <@ari:example.org> earlier\n> more\nthe answer", ["answer"]),
          "the answer");
    });

    test("long bodies are cut around the first match", () {
      final body = "${"word " * 30}matcha latte${" word" * 30}";
      final s = deepSearchSnippet(body, ["matcha"], radius: 20);
      expect(s, contains("matcha latte"));
      expect(s.startsWith("…"), isTrue);
      expect(s.endsWith("…"), isTrue);
      expect(s.length, lessThan(60));
    });

    test("no match keeps the start", () {
      final body = "x" * 200;
      expect(deepSearchSnippet(body, ["tea"], radius: 10), "${"x" * 20}…");
    });
  });

  group("deepSearchCollapse", () {
    test("nearby hits in one chat fold under the first", () {
      final rows = deepSearchCollapse([
        _hit("a", ts: 0),
        _hit("b", ts: 5 * _minute),
        _hit("c", ts: 10 * _minute),
        _hit("d", room: "!other:example.org", ts: 11 * _minute),
      ]);
      expect(rows.length, 2);
      expect(rows[0].result.eventId, "a");
      expect([for (final r in rows[0].more) r.eventId], ["b", "c"]);
      expect(rows[1].result.eventId, "d");
    });

    test("hits far apart, or on another account, stay apart", () {
      final rows = deepSearchCollapse([
        _hit("a", ts: 0),
        _hit("b", ts: 31 * _minute),
        _hit("c", ts: 32 * _minute, account: "acct-b"),
      ]);
      expect(rows.length, 3);
      expect(rows.every((r) => r.more.isEmpty), isTrue);
    });

    test("an expanded group shows every hit", () {
      final rows = deepSearchCollapse(
          [_hit("a", ts: 0), _hit("b", ts: _minute)],
          expanded: {"a"});
      expect([for (final r in rows) r.result.eventId], ["a", "b"]);
    });
  });

  group("deepSearchStep", () {
    test("steps within the list", () {
      expect(deepSearchStep(2, 5, 1), 3);
      expect(deepSearchStep(2, 5, -1), 1);
    });
    test("stops at the ends", () {
      expect(deepSearchStep(4, 5, 1), isNull);
      expect(deepSearchStep(0, 5, -1), isNull);
      expect(deepSearchStep(null, 0, 1), isNull);
    });
    test("nothing open starts at an end", () {
      expect(deepSearchStep(null, 5, 1), 0);
      expect(deepSearchStep(null, 5, -1), 4);
    });
  });

  test("the strip's count caps at 99+", () {
    expect(deepSearchStripCount(9), "9");
    expect(deepSearchStripCount(99), "99");
    expect(deepSearchStripCount(100), "99+");
    expect(deepSearchStripCount(99, capped: true), "99+");
  });

  group("DeepSearchMarks", () {
    test("marks seen and last opened for one search", () {
      final marks = DeepSearchMarks()..forSearch("tea");
      final a = _hit("a");
      final b = _hit("b");
      marks.opened(a);
      marks.opened(b);
      expect(marks.isSeen(a), isTrue);
      expect(marks.isLastOpened(a), isFalse);
      expect(marks.isLastOpened(b), isTrue);
      expect(marks.seenCount, 2);
      marks.forSearch("tea");
      expect(marks.seenCount, 2);
    });

    test("a new search starts afresh", () {
      final marks = DeepSearchMarks()..forSearch("tea");
      marks.opened(_hit("a"));
      marks.forSearch("coffee");
      expect(marks.seenCount, 0);
      expect(marks.isSeen(_hit("a")), isFalse);
    });
  });

  test("the results bar runs through local, then server hits", () {
    final local = _hit("a");
    final server = _hit("b", source: DeepSearchSource.server);
    final results = DeepSearchResults(local: [local], server: [server]);
    expect(
        [for (final r in deepSearchOpenOrder(results)) r.eventId], ["a", "b"]);
  });
}
