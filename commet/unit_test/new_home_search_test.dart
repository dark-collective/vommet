// Vommet (New Home): the side list search engine: folding, ranking, the
// groups (each room once), scopes, chips, snippets, and that a keystroke
// stays fast with many rooms.
import 'package:commet/ui/organisms/new_home/new_home_search.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime _at(int minute) =>
    DateTime.utc(2026, 10, 26).add(Duration(minutes: minute));

SearchDoc<String, String> _doc(String name, int minute,
        {List<String> path = const [],
        List<String> tags = const [],
        String topic = "",
        bool dm = false,
        String? partner}) =>
    SearchDoc(
      room: name,
      name: name,
      partner: partner,
      path: path,
      pathNames: path,
      tags: [for (final t in tags) "u.$t"],
      tagNames: tags,
      topic: topic,
      isDirectMessage: dm,
      last: _at(minute),
    );

SearchSpace<String> _space(List<String> path) =>
    SearchSpace(path.last, path.last, path,
        parentName: path.length > 1 ? path[path.length - 2] : null);

final _index = SearchIndex<String, String>([
  _doc("Alice", 90, dm: true, partner: "@alice:example.org"),
  _doc("Dev chat", 80, path: ["Nether", "Software Development"]),
  _doc("Builds", 70, path: ["Nether", "Software Development", "Infra"]),
  _doc("General", 60, path: ["Nether"], topic: "Welcome! Say hi."),
  _doc("Lounge", 50, topic: "Talk about developers and their tools"),
  _doc("Raid night", 40, path: ["Guild"], tags: ["Developers"]),
  _doc("Café", 30),
  _doc("Old dev notes", 20),
  _doc("Rust", 10, path: ["Nether", "Software Development"]),
  _doc("Go", 5, path: ["Nether", "Software Development"]),
], [
  _space(["Nether"]),
  _space(["Nether", "Software Development"]),
  _space(["Nether", "Software Development", "Infra"]),
  _space(["Guild"]),
  _space(["Guild", "Infra"]),
]);

List<String> _names(List<SearchHit<String>> hits) =>
    [for (final h in hits) h.room];

void main() {
  group("Matching", () {
    test("folds case and accents, one code unit each", () {
      expect(searchFold("Café ÉLAN"), "cafe elan");
      expect(searchFold("Ünïcödé").length, "Ünïcödé".length);
    });

    test("start, word start, inside", () {
      expect(matchRank("dev chat", "dev"), 0);
      expect(matchRank("old dev notes", "dev"), 1);
      expect(matchRank("abdevx", "dev"), 2);
      expect(matchRank("lounge", "dev"), isNull);
    });

    test("rankByName: prefix before word before inside, then newest", () {
      final items = ["xdev", "Old dev", "Dev B", "Dev A"];
      final last = {"xdev": 4, "Old dev": 3, "Dev B": 1, "Dev A": 2};
      expect(
          rankByName<String>(items, "dev",
              name: (s) => s, last: (s) => _at(last[s]!)),
          ["Dev A", "Dev B", "Old dev", "xdev"]);
    });
  });

  group("Groups", () {
    test("NAME, then IN <space>, TAGGED, TOPIC; each room once", () {
      final r = _index.search("dev");
      expect(_names(r.names), ["Dev chat", "Old dev notes"]);
      // Rooms in Software Development (subspace rooms under their
      // deepest matching space).
      expect([for (final g in r.inSpaces) g.label],
          ["Nether › Software Development"]);
      expect(_names(r.inSpaces.single.hits), ["Builds", "Rust", "Go"]);
      expect([for (final g in r.tagged) g.label], ["Developers"]);
      expect(_names(r.tagged.single.hits), ["Raid night"]);
      expect(_names(r.topics), ["Lounge"]);
      expect([for (final s in r.spaces) s.name], ["Software Development"]);
    });

    test("a DM matches by its person's id too", () {
      final r = _index.search("@alice");
      expect(_names(r.names), ["Alice"]);
      expect(r.names.single.start, -1);
    });

    test("accents don't matter; the hit is marked in the name", () {
      final r = _index.search("cafe");
      expect(_names(r.names), ["Café"]);
      expect((r.names.single.start, r.names.single.end), (0, 4));
    });

    test("topic snippets mark the hit", () {
      final hit = _index.search("hi").topics.single;
      expect(hit.room, "General");
      final s = hit.snippet!;
      expect(s.text.substring(s.start, s.end), "hi");
    });

    test("same-named spaces show their parent", () {
      final infra = _index.spaces.where((s) => s.name == "Infra").toList();
      expect([for (final s in infra) _index.spaceLabel(s)],
          ["Infra · Software Development", "Infra · Guild"]);
    });

    test("order: names, then each group's first three unless expanded", () {
      final r = _index.search("dev");
      expect(r.order(), [
        "Dev chat",
        "Old dev notes",
        "Builds",
        "Rust",
        "Go",
        "Raid night",
        "Lounge",
      ]);
      expect(r.order(shownIn: 1),
          ["Dev chat", "Old dev notes", "Builds", "Raid night", "Lounge"]);
      expect(r.order(shownIn: 1, expanded: {"Software Development"}).length, 7);
    });
  });

  group("Scopes", () {
    const nether = SearchScope<String>.space("Nether", ["Nether"], "Nether");
    const dev = SearchScope<String>.space("Software Development",
        ["Nether", "Software Development"], "Software Development");

    test("a space scope with no text: its rooms, newest first", () {
      final r = _index.search("", scope: dev);
      expect(_names(r.names), ["Dev chat", "Builds", "Rust", "Go"]);
      // Its subspaces narrow it.
      expect([for (final (s, n) in r.spaceChips) "${s.name} $n"], ["Infra 1"]);
    });

    test("typing inside a scope; space labels relative to it", () {
      final r = _index.search("infra", scope: nether);
      expect([for (final g in r.inSpaces) g.label],
          ["Software Development › Infra"]);
      expect(_names(r.inSpaces.single.hits), ["Builds"]);
      expect(_index.search("lounge", scope: nether).isEmpty, isTrue);
    });

    test("tag and kind scopes", () {
      expect(
          _names(_index
              .search("", scope: const SearchScope.tag("u.Developers", "Dev"))
              .names),
          ["Raid night"]);
      final dms = _index.search("a", scope: const SearchScope.kind(true));
      expect(_names(dms.names), ["Alice"]);
      expect(dms.rooms, 0);
    });

    test("chips count the matches", () {
      final r = _index.search("dev");
      expect(r.directMessages, 0);
      expect(r.rooms, 7);
      expect([for (final (_, name, n) in r.tagChips) "$name $n"],
          ["Developers 1"]);
      expect([for (final (s, n) in r.spaceChips) "${s.name} $n"],
          ["Software Development 4"]);
    });
  });

  test("a keystroke over 2,000 rooms and 200 spaces stays fast", () {
    final docs = [
      for (var i = 0; i < 2000; i++)
        _doc("Room $i ${i.isEven ? "general" : "dev"}", i,
            path: ["Space ${i % 200}", "Sub ${i % 7}"],
            tags: [if (i % 10 == 0) "Tag ${i % 30}"],
            topic: "Topic number $i about things " * 4)
    ];
    final spaces = [
      for (var i = 0; i < 200; i++) _space(["Space $i"])
    ];
    final index = SearchIndex(docs, spaces);
    // Warm up, then time a few keystrokes.
    index.search("d");
    final watch = Stopwatch()..start();
    for (final q in ["d", "de", "dev", "devx", "sub 3", "topic 19"]) {
      index.search(q);
    }
    watch.stop();
    // About 8 ms a keystroke is the aim; CI machines vary, so be generous.
    expect(watch.elapsedMilliseconds / 6, lessThan(80));
  });
}
