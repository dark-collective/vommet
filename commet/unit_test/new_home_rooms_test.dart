import 'package:commet/ui/organisms/new_home/new_home_rooms_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A stand-in room.
class _R {
  const _R(this.name, this.minute,
      {this.kind = RoomKind.chat, this.unread = false});
  final String name;
  final int minute;
  final RoomKind kind;
  final bool unread;

  @override
  String toString() => name;
}

final _facts = RoomFacts<_R>(
  name: (r) => r.name,
  kind: (r) => r.kind,
  unread: (r) => r.unread,
  lastActivity: (r) => DateTime(2026, 10, 22).add(Duration(minutes: r.minute)),
);

SpaceNode<String, _R> _space(String name,
        {List<_R> rooms = const [],
        List<SpaceNode<String, _R>> subspaces = const []}) =>
    SpaceNode(name, name, "space:$name", rooms: rooms, subspaces: subspaces);

const _lounge = _R("Lounge", 5);
const _retroChat = _R("retro-chat", 9, unread: true);
const _voice = _R("Voice Hangout", 3, kind: RoomKind.voice);
const _snes = _R("SNES Retro Night", 7, kind: RoomKind.voice, unread: true);
const _photos = _R("Retro photos", 1, kind: RoomKind.photos);
const _cal = _R("Meetups", 2, kind: RoomKind.calendar);
const _books = _R("Book talk", 4);

final _standalone = [_lounge, _retroChat];

/// Gaming Guild › Retro › Consoles, and Book Club.
final _spaces = [
  _space("Gaming Guild", rooms: [
    _voice
  ], subspaces: [
    _space("Retro", rooms: [
      _photos
    ], subspaces: [
      _space("Consoles", rooms: [_snes, _cal]),
    ]),
  ]),
  _space("Book Club", rooms: [_books]),
];

List<RoomsHit<String, _R>> _search(String q, RoomsChip chip) =>
    RoomsModel.search(
        query: q,
        standalone: _standalone,
        spaces: _spaces,
        chip: chip,
        facts: _facts,
        identity: (r) => r.name);

void main() {
  group("match", () {
    test("start, then a word start, then anywhere; any case", () {
      final start = RoomsModel.match("Retro photos", "ret")!;
      expect([start.start, start.end, start.score], [0, 3, 0]);
      final word = RoomsModel.match("SNES Retro Night", "RET")!;
      expect([word.start, word.end, word.score], [5, 8, 1]);
      final dash = RoomsModel.match("old-retro", "retro")!;
      expect(dash.score, 1);
      final inside = RoomsModel.match("Theretrospective", "retro")!;
      expect([inside.start, inside.score], [3, 2]);
      expect(RoomsModel.match("Lounge", "xyz"), isNull);
      expect(RoomsModel.match("Lounge", "  "), isNull);
    });
  });

  group("tree", () {
    test("All: standalone first (newest first), then spaces with nesting", () {
      final tree = RoomsModel.tree<String, _R>(
          standalone: _standalone,
          spaces: _spaces,
          chip: RoomsChip.all,
          facts: _facts);
      expect(tree.sections.map((s) => s.name),
          ["Standalone rooms", "Gaming Guild", "Book Club"]);
      expect(tree.sections[0].rooms, [_retroChat, _lounge]);
      final guild = tree.sections[1];
      expect(guild.count, 4);
      expect(guild.subspaceCount, 2);
      expect(guild.subsections.single.name, "Retro");
      expect(guild.subsections.single.depth, 1);
      expect(guild.subsections.single.subsections.single.rooms, [_snes, _cal]);
      expect(RoomsModel.unreadIn(guild, _facts), 1);
      expect(RoomsModel.collapsedSummary(guild, 1), "2 subspaces · 1 unread");
      expect(RoomsModel.collapsedSummary(tree.sections[2], 0), "");
    });

    test("Standalone: only rooms outside spaces", () {
      final tree = RoomsModel.tree<String, _R>(
          standalone: _standalone,
          spaces: _spaces,
          chip: RoomsChip.standalone,
          facts: _facts);
      expect(tree.sections.single.node, isNull);
      expect(tree.sections.single.count, 2);
    });

    test("Voice keeps the path to voice rooms and names spaces without", () {
      final tree = RoomsModel.tree<String, _R>(
          standalone: _standalone,
          spaces: _spaces,
          chip: RoomsChip.voice,
          facts: _facts);
      expect(tree.sections.map((s) => s.name), ["Gaming Guild"]);
      final guild = tree.sections.single;
      expect(guild.rooms, [_voice]);
      expect(guild.subsections.single.rooms, isEmpty);
      expect(guild.subsections.single.subsections.single.rooms, [_snes]);
      expect(tree.without, ["Book Club"]);
      expect(RoomsModel.withoutNote(tree.without, RoomsChip.voice),
          "Book Club has no voice rooms.");
      expect(RoomsModel.withoutNote(["A", "B", "C"], RoomsChip.calendars),
          "A, B and C have no calendars.");
    });

    test("Unread, Photos and Calendars filter by the real types", () {
      List<String> names(RoomsChip chip) {
        final tree = RoomsModel.tree<String, _R>(
            standalone: _standalone,
            spaces: _spaces,
            chip: chip,
            facts: _facts);
        final out = <String>[];
        void walk(RoomsSection<String, _R> s) {
          out.addAll(s.rooms.map((r) => r.name));
          s.subsections.forEach(walk);
        }

        tree.sections.forEach(walk);
        return out;
      }

      expect(names(RoomsChip.unread), ["retro-chat", "SNES Retro Night"]);
      expect(names(RoomsChip.photos), ["Retro photos"]);
      expect(names(RoomsChip.calendars), ["Meetups"]);
    });

    test("a space that contains itself doesn't loop", () {
      final cyclic = SpaceNode<String, _R>("A", "A", "space:a", rooms: [
        _lounge
      ], subspaces: [
        SpaceNode("A again", "A again", "space:a", rooms: [_books])
      ]);
      final tree = RoomsModel.tree<String, _R>(
          standalone: const <_R>[],
          spaces: [cyclic],
          chip: RoomsChip.all,
          facts: _facts);
      expect(tree.sections.single.subsections, isEmpty);
    });
  });

  group("search", () {
    test("finds rooms in nested subspaces with a breadcrumb", () {
      final hits = _search("ret", RoomsChip.all);
      final byName = {for (final h in hits) h.name: h};
      expect(byName.keys,
          containsAll(["retro-chat", "Retro photos", "SNES Retro Night"]));
      expect(byName["SNES Retro Night"]!.breadcrumb,
          "Gaming Guild › Retro › Consoles");
      expect(byName["Retro photos"]!.breadcrumb, "Gaming Guild › Retro");
      expect(byName["retro-chat"]!.breadcrumb, "Standalone");
    });

    test("spaces and subspaces match too, under All only", () {
      final all = _search("retro", RoomsChip.all);
      final retro = all.firstWhere((h) => h.isSpace);
      expect(retro.name, "Retro");
      expect(retro.breadcrumb, "Gaming Guild");
      expect(_search("gaming", RoomsChip.all).single.breadcrumb, "Space");
      expect(_search("retro", RoomsChip.voice).any((h) => h.isSpace), isFalse);
    });

    test("best match first, rooms before spaces, newest first", () {
      final hits = _search("ret", RoomsChip.all);
      expect(hits.map((h) => h.name), [
        "retro-chat", // starts with it, newest
        "Retro photos", // starts with it
        "Retro", // a space
        "SNES Retro Night", // a word starts with it
      ]);
    });

    test("chips filter the hits and count them", () {
      expect(_search("ret", RoomsChip.voice).map((h) => h.name),
          ["SNES Retro Night"]);
      expect(_search("ret", RoomsChip.standalone).map((h) => h.name),
          ["retro-chat"]);
      final counts = RoomsModel.searchCounts(
          query: "ret",
          standalone: _standalone,
          spaces: _spaces,
          facts: _facts,
          identity: (r) => r.name);
      expect(counts, {
        RoomsChip.all: 4,
        RoomsChip.standalone: 1,
        RoomsChip.voice: 1,
        RoomsChip.photos: 1,
        RoomsChip.calendars: 0,
        RoomsChip.unread: 2,
      });
      expect(RoomsModel.chipLabel(RoomsChip.all, 4, phone: false),
          "All rooms & spaces 4");
      expect(RoomsModel.chipLabel(RoomsChip.all, null, phone: true), "All");
    });

    test("a room in two spaces shows once", () {
      final shared = SpaceNode<String, _R>("Other", "Other", "space:other",
          rooms: [_photos]);
      final hits = RoomsModel.search<String, _R>(
          query: "photos",
          standalone: const <_R>[],
          spaces: [..._spaces, shared],
          chip: RoomsChip.all,
          facts: _facts,
          identity: (r) => r.name);
      expect(hits.where((h) => !h.isSpace).length, 1);
      expect(hits.firstWhere((h) => !h.isSpace).breadcrumb,
          "Gaming Guild › Retro");
    });
  });

  group("collapsed sections, remembered per chip", () {
    test("each chip keeps its own", () {
      var stored = <String>[];
      stored = RoomsModel.withCollapsed(
          stored, RoomsChip.all, ["standalone", "space:a"],
          collapsed: true);
      stored = RoomsModel.withCollapsed(stored, RoomsChip.voice, ["space:b"],
          collapsed: true);
      expect(RoomsModel.collapsedFor(stored, RoomsChip.all),
          {"standalone", "space:a"});
      expect(RoomsModel.collapsedFor(stored, RoomsChip.voice), {"space:b"});
      expect(RoomsModel.collapsedFor(stored, RoomsChip.unread), isEmpty);
    });

    test("expanding removes only that chip's entries", () {
      var stored = RoomsModel.withCollapsed(
          [], RoomsChip.all, ["standalone", "space:a"],
          collapsed: true);
      stored = RoomsModel.withCollapsed(stored, RoomsChip.voice, ["space:a"],
          collapsed: true);
      stored = RoomsModel.withCollapsed(stored, RoomsChip.all, ["space:a"],
          collapsed: false);
      expect(RoomsModel.collapsedFor(stored, RoomsChip.all), {"standalone"});
      expect(RoomsModel.collapsedFor(stored, RoomsChip.voice), {"space:a"});
    });

    test("collapsing twice stores one entry", () {
      var stored = RoomsModel.withCollapsed([], RoomsChip.all, ["space:a"],
          collapsed: true);
      stored = RoomsModel.withCollapsed(stored, RoomsChip.all, ["space:a"],
          collapsed: true);
      expect(stored, hasLength(1));
    });
  });

  testWidgets("a section of 600 rooms: built lazily, all reachable",
      (tester) async {
    final rooms = [for (var i = 0; i < 600; i++) _R("Room $i", 600 - i)];
    final tree = RoomsModel.tree<String, _R>(
        standalone: rooms,
        spaces: _spaces,
        chip: RoomsChip.standalone,
        facts: _facts);
    final section = tree.sections.single;
    final visible = section.rooms.length;
    expect(visible, 600);

    // The page lists its rows with a ListView.builder like this one.
    var built = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView.builder(
          itemCount: visible,
          itemBuilder: (context, i) {
            built++;
            return SizedBox(height: 44, child: Text(section.rooms[i].name));
          },
        ),
      ),
    ));
    expect(built, lessThan(60), reason: "rows must be built lazily");
    expect(find.text("Room 0"), findsOneWidget);

    await tester.scrollUntilVisible(find.text("Room 599"), 2000);
    expect(find.text("Room 599"), findsOneWidget);
    expect(find.text("Room 0"), findsNothing);
  });
}
