import 'package:commet/ui/organisms/new_home/new_home_layout.dart';
import 'package:commet/ui/organisms/new_home/new_home_tabs.dart';
import 'package:commet/ui/organisms/new_home/room_tags.dart';
import 'package:flutter_test/flutter_test.dart';

/// A stand-in room for [sideListRooms]: a name, a minute of its last
/// message and its tags.
class _R {
  const _R(this.name, this.minute, [this.tags = const {}]);
  final String name;
  final int minute;
  final Set<String> tags;

  @override
  String toString() => name;
}

List<List<String>> _side(List<HomeSection> sections, List<_R> rooms) =>
    sideListRooms<_R>(
      sections,
      rooms,
      SideListFacts(
        lastEvent: (r) =>
            DateTime.utc(2026, 10, 22).add(Duration(minutes: r.minute)),
        isFavourite: (r) => r.tags.contains("m.favourite"),
        isDirectMessage: (r) => false,
        isVoice: (r) => false,
        isLive: (r) => false,
        isPhotos: (r) => false,
        isStandalone: (r) => false,
        isLowPriority: (r) => r.tags.contains("m.lowpriority"),
        spaceRooms: (s) => null,
        hasTag: (r, tag) => r.tags.contains(tag),
      ),
    ).map((list) => list.map((r) => r.name).toList()).toList();

void main() {
  group("Room tags", () {
    test("only u.* tags are yours, shown without the prefix", () {
      expect(isUserTag("u.Gaming"), isTrue);
      expect(isUserTag("u."), isFalse);
      expect(isUserTag("m.favourite"), isFalse);
      expect(isUserTag("m.server_notice"), isFalse);
      expect(isUserTag("im.nheko.thing"), isFalse);
      expect(tagName("u.Gaming"), "Gaming");
      expect(tagName("m.favourite"), "m.favourite");
    });

    test("a typed name becomes u.<name>, trimmed and capped", () {
      expect(tagFromName("  Work stuff "), "u.Work stuff");
      expect(tagFromName("   "), isNull);
      expect(tagFromName(""), isNull);
      final long = tagFromName("x" * 100)!;
      expect(long.length, userTagPrefix.length + maxTagName);
    });

    test("your tags across rooms: each once, sorted by name ignoring case", () {
      final rooms = [
        ["u.zeta", "m.favourite"],
        ["u.Alpha", "u.zeta"],
        ["m.lowpriority", "u.beta"],
        <String>[],
      ];
      expect(userTagsOf(rooms), ["u.Alpha", "u.beta", "u.zeta"]);
      expect(userTagCounts(rooms), {"u.zeta": 2, "u.Alpha": 1, "u.beta": 1});
    });
  });

  group("Tag sections", () {
    test("a tag section lists the rooms with its tag, newest first", () {
      final rooms = [
        const _R("old", 1, {"u.Gaming"}),
        const _R("new", 9, {"u.Gaming", "u.Work"}),
        const _R("other", 5, {"u.Work"}),
      ];
      expect(
          _side([
            const HomeSection("tag-a1",
                type: HomeSection.tagSection, tag: "u.Gaming"),
          ], rooms),
          [
            ["new", "old"]
          ]);
    });

    test("a tag section without a tag shows nothing", () {
      expect(
          _side([
            const HomeSection("tag-a1", type: HomeSection.tagSection)
          ], [
            const _R("r", 1, {"u.Gaming"})
          ]),
          [<String>[]]);
    });

    test("All my tags makes a section per tag not shown on its own", () {
      const sections = [
        HomeSection("tag-a1", type: HomeSection.tagSection, tag: "u.Work"),
        HomeSection(HomeSection.allTags, collapsedTags: ["u.Gaming"]),
        HomeSection(HomeSection.recent),
      ];
      final shown =
          expandTagSections(sections, ["u.Art", "u.Gaming", "u.Work"]);
      expect([for (final s in shown) s.id],
          ["tag-a1", "all_tags/u.Art", "all_tags/u.Gaming", "recent"]);
      expect(shown[1].type, HomeSection.tagSection);
      expect(shown[1].tag, "u.Art");
      expect(shown[1].parent, HomeSection.allTags);
      expect(shown[1].collapsed, isFalse);
      expect(shown[2].collapsed, isTrue);
      // Nothing to show: All my tags adds no sections.
      expect(expandTagSections(sections, []).map((s) => s.id),
          ["tag-a1", "recent"]);
    });

    test("collapsing a tag in All my tags is remembered on it", () {
      const all = HomeSection(HomeSection.allTags);
      final once = toggleCollapsedTag(all, "u.Gaming");
      expect(once.collapsedTags, ["u.Gaming"]);
      expect(toggleCollapsedTag(once, "u.Gaming").collapsedTags, isEmpty);
    });

    test("tag sections round-trip; parent is never saved", () {
      const tag = HomeSection("tag-a1",
          type: HomeSection.tagSection, tag: "u.Gaming", collapsed: true);
      final json = tag.toJson();
      expect(json["tag"], "u.Gaming");
      expect(HomeSection.fromJson(json)!, tag);
      const all = HomeSection(HomeSection.allTags,
          collapsedTags: ["u.Art"], parent: "x");
      expect(all.toJson().containsKey("parent"), isFalse);
      expect(HomeSection.fromJson(all.toJson())!.collapsedTags, ["u.Art"]);
    });

    test("tag sections can be added any number of times, All my tags once", () {
      const tab = HomeTab("t",
          name: "T",
          side: [HomeSection(HomeSection.allTags)],
          main: HomeLayout([]));
      expect(tab.canAddSection(HomeSection.tagSection), isTrue);
      expect(tab.canAddSection(HomeSection.allTags), isFalse);
      expect(tab.newSectionId(HomeSection.tagSection),
          isNot(HomeSection.tagSection));
    });
  });

  group("Tag cards", () {
    test("a Tag card keeps its tag; there can be several", () {
      final card = const HomeLayout([])
          .newCard(HomeLayout.tagCard)
          .copyWith(tag: "u.Gaming");
      final back = HomeCard.fromJson(card.toJson())!;
      expect(back.type, HomeLayout.tagCard);
      expect(back.tag, "u.Gaming");
      expect(back, card);
      expect(HomeLayout.multiTypes.contains(HomeLayout.tagCard), isTrue);
      expect(HomeLayout.multiTypes.contains(HomeLayout.allTagsCard), isFalse);
      expect(HomeLayout.knownTypes, containsAll(HomeLayout.tagTypes));
    });
  });
}
