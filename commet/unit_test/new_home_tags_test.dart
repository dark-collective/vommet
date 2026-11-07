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
        hasUserTag: (r) => r.tags.any(isUserTag),
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
                type: HomeSection.tagSection, tags: ["u.Gaming"]),
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
        HomeSection("tag-a1", type: HomeSection.tagSection, tags: ["u.Work"]),
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
          type: HomeSection.tagSection, tags: ["u.Gaming"], collapsed: true);
      final json = tag.toJson();
      expect(json["tag"], "u.Gaming");
      expect(HomeSection.fromJson(json)!, tag);
      const all = HomeSection(HomeSection.allTags,
          collapsedTags: ["u.Art"], parent: "x");
      expect(all.toJson().containsKey("parent"), isFalse);
      expect(HomeSection.fromJson(all.toJson())!.collapsedTags, ["u.Art"]);
    });

    test("Tags sections can be added any number of times", () {
      const tab = HomeTab("t",
          name: "T",
          side: [HomeSection(HomeSection.allTags)],
          main: HomeLayout([]));
      expect(tab.canAddSection(HomeSection.tagSection), isTrue);
      expect(tab.canAddSection(HomeSection.allTags), isTrue);
      expect(tab.newSectionId(HomeSection.tagSection),
          isNot(HomeSection.tagSection));
    });
  });

  group("Tags sections (round 4)", () {
    test("Pick tags with several tags makes a section per picked tag", () {
      const picked = HomeSection("tag-a1",
          type: HomeSection.tagSection,
          tags: ["u.Garden", "u.Gaming"],
          collapsedTags: ["u.Gaming"]);
      final shown = expandTagSections([picked], ["u.Art", "u.Gaming"]);
      expect([for (final s in shown) s.id],
          ["tag-a1/u.Garden", "tag-a1/u.Gaming"]);
      expect(shown.map((s) => s.parent), everyElement("tag-a1"));
      expect(shown[1].collapsed, isTrue);
      // Collapsing one is remembered on the picked section.
      expect(toggleCollapsedTag(picked, "u.Garden").collapsedTags,
          ["u.Gaming", "u.Garden"]);
    });

    test("one list stays one section: rooms with ANY picked tag, once", () {
      const list = HomeSection("tag-a1",
          type: HomeSection.tagSection,
          tags: ["u.Garden", "u.Gaming"],
          tagList: true);
      expect(expandTagSections([list], ["u.Garden", "u.Gaming"]), [list]);
      final rooms = [
        const _R("both", 3, {"u.Garden", "u.Gaming"}),
        const _R("garden", 7, {"u.Garden"}),
        const _R("work", 9, {"u.Work"}),
        const _R("gaming", 1, {"u.Gaming"}),
      ];
      expect(_side([list], rooms), [
        ["garden", "both", "gaming"]
      ]);
    });

    test("All my tags as one list: every room with one of your tags", () {
      const all =
          HomeSection(HomeSection.allTags, tagList: true, name: "Tagged");
      expect(expandTagSections([all], ["u.Art"]), [all]);
      expect(
          _side([
            all
          ], [
            const _R("fav", 5, {"m.favourite"}),
            const _R("art", 2, {"u.Art"}),
          ]),
          [
            ["art"]
          ]);
    });

    test("All my tags skips tags a Pick tags section shows", () {
      const sections = [
        HomeSection("tag-a1",
            type: HomeSection.tagSection,
            tags: ["u.Art", "u.Work"],
            tagList: true),
        HomeSection(HomeSection.allTags),
      ];
      expect(
          expandTagSections(sections, ["u.Art", "u.Gaming", "u.Work"])
              .map((s) => s.id),
          ["tag-a1", "all_tags/u.Gaming"]);
    });

    test("a section from before reads as Pick tags with its one tag", () {
      final old = HomeSection.fromJson(
          {"id": "tag-a1", "type": "tag", "tag": "u.Gaming"})!;
      expect(old.tags, ["u.Gaming"]);
      expect(old.tagList, isFalse);
      // Written back exactly as before.
      expect(old.toJson(), {"id": "tag-a1", "type": "tag", "tag": "u.Gaming"});
    });

    test("picked tags, list and name round-trip; first tag kept in tag", () {
      const s = HomeSection("tag-a1",
          type: HomeSection.tagSection,
          tags: ["u.Garden", "u.Gaming"],
          tagList: true,
          name: "Hobbies");
      final json = s.toJson();
      expect(json["tag"], "u.Garden");
      expect(json["tags"], ["u.Garden", "u.Gaming"]);
      expect(json["showAs"], "list");
      expect(json["name"], "Hobbies");
      expect(HomeSection.fromJson(json), s);
    });

    test("switching mode changes the type; the id stays", () {
      const all = HomeSection(HomeSection.allTags);
      final picked =
          all.copyWith(type: HomeSection.tagSection, tags: ["u.Art"]);
      expect(picked.id, HomeSection.allTags);
      expect(picked.type, HomeSection.tagSection);
      expect(picked.toJson()["type"], "tag");
      expect(HomeSection.fromJson(picked.toJson()), picked);
      final back = picked.copyWith(type: HomeSection.allTags, tags: const []);
      expect(back.toJson().containsKey("type"), isFalse);
      expect(picked.copyWith(name: "X").copyWith(name: "").name, isNull);
    });
  });

  group("Tags card", () {
    test("a Tags card keeps its tags; there can be several", () {
      final card = const HomeLayout([])
          .newCard(HomeLayout.tagCard)
          .copyWith(tags: ["u.Gaming"]);
      final back = HomeCard.fromJson(card.toJson())!;
      expect(back.type, HomeLayout.tagCard);
      expect(back.tag, "u.Gaming");
      expect(back, card);
      expect(HomeLayout.multiTypes, containsAll(HomeLayout.tagTypes));
      expect(HomeLayout.configurableTypes, containsAll(HomeLayout.tagTypes));
      expect(HomeLayout.knownTypes, containsAll(HomeLayout.tagTypes));
    });

    test("a Tag card from before becomes Pick tags with its tag", () {
      final old = HomeCard.fromJson({
        "id": "tag-p0q1r2",
        "type": "tag",
        "hidden": false,
        "options": {"tag": "u.Gaming", "unreadOnly": false}
      })!;
      expect(old.tags, ["u.Gaming"]);
      expect(old.tagList, isFalse);
      expect(old.name, isNull);
      expect(old.toJson(), {
        "id": "tag-p0q1r2",
        "type": "tag",
        "hidden": false,
        "options": {"tag": "u.Gaming", "unreadOnly": false}
      });
    });

    test("All my tags from before stays All my tags", () {
      final old = HomeCard.fromJson({"id": "all_tags", "hidden": false})!;
      expect(old.type, HomeLayout.allTagsCard);
      expect(old.tags, isEmpty);
      expect(
          tagsTitle(all: true, tags: old.tags, name: old.name), "All my tags");
    });

    test("several picked tags: first one in tag for older versions", () {
      final card = const HomeCard("tag-a1", type: HomeLayout.tagCard)
          .copyWith(tags: ["u.Garden", "u.Gaming"], tagList: true, name: "H");
      final options = card.toJson()["options"] as Map;
      expect(options["tag"], "u.Garden");
      expect(options["tags"], ["u.Garden", "u.Gaming"]);
      expect(options["showAs"], "list");
      expect(options["name"], "H");
      expect(HomeCard.fromJson(card.toJson()), card);
    });

    test("broken tags fall back to tag; duplicates go", () {
      final card = HomeCard.fromJson({
        "id": "tag-a1",
        "type": "tag",
        "options": {
          "tag": "u.Art",
          "tags": ["u.Art", 3, "", "u.Art", "u.Work"]
        }
      })!;
      expect(card.tags, ["u.Art", "u.Work"]);
      expect(
          HomeCard.fromJson({
            "id": "tag-a1",
            "type": "tag",
            "options": {"tag": "u.Art", "tags": "nope"}
          })!
              .tags,
          ["u.Art"]);
    });

    test("switching to All my tags keeps the id and the name", () {
      final picked = const HomeCard("tag-a1", type: HomeLayout.tagCard)
          .copyWith(tags: ["u.Art"], name: "Mine");
      final all = picked.copyWith(type: HomeLayout.allTagsCard, tags: const []);
      expect(all.id, "tag-a1");
      expect(all.type, HomeLayout.allTagsCard);
      final back = HomeCard.fromJson(all.toJson())!;
      expect(back, all);
      expect(back.name, "Mine");
      expect(back.tag, isNull);
    });

    test("the name defaults to the tag names; the summary says how", () {
      expect(tagsTitle(all: false, tags: ["u.Gaming", "u.Garden"]),
          "Gaming, Garden");
      expect(tagsTitle(all: false, tags: const []), "Tags");
      expect(tagsTitle(all: false, tags: ["u.Gaming"], name: "Fun"), "Fun");
      final card = const HomeCard("tag-a1", type: HomeLayout.tagCard)
          .copyWith(tags: ["u.Gaming", "u.Garden"]);
      expect(cardSummary(card), "Gaming, Garden · a section per tag");
      expect(cardSummary(const HomeCard("all_tags").copyWith(tagList: true)),
          "All my tags · one list");
    });
  });
}
