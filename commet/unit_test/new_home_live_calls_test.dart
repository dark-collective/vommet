import 'package:commet/ui/organisms/new_home/new_home_layout.dart';
import 'package:commet/ui/organisms/new_home/new_home_live_calls_model.dart';
import 'package:commet/ui/organisms/new_home/new_home_tabs.dart';
import 'package:flutter_test/flutter_test.dart';

// Vommet (New Home cards, round 4): the Live calls card.

/// A stand-in room: a name, who's in its call, when it began (minutes
/// after 10:00) and what kind of room it is.
class _R {
  const _R(this.name, this.people,
      {this.minute,
      this.dm = false,
      this.muted = false,
      this.low = false,
      this.favourite = false,
      this.space = false});
  final String name;
  final List<String> people;
  final int? minute;
  final bool dm, muted, low, favourite, space;
}

List<String> _calls(List<_R> rooms, HomeCard card) => liveCallsOf<_R>(
      rooms,
      card,
      participants: (r) => r.people,
      startedAt: (r) => r.minute == null
          ? null
          : DateTime.utc(2026, 10, 24, 10).add(Duration(minutes: r.minute!)),
      isDirectMessage: (r) => r.dm,
      isMuted: (r) => r.muted,
      isLowPriority: (r) => r.low,
      isFavourite: (r) => r.favourite,
      inSpace: (r) => r.space,
    ).map((c) => c.room.name).toList();

const _card = HomeCard(HomeLayout.liveCalls);

void main() {
  group("Which calls show", () {
    const rooms = [
      _R("quiet", []),
      _R("owls", ["@q:x"], minute: 40),
      _R("fireside", ["@a:x", "@b:x", "@c:x"], minute: 2, favourite: true),
      _R("muted", ["@a:x"], minute: 1, muted: true),
      _R("low", ["@a:x"], minute: 1, low: true),
      _R("dm", ["@a:x", "@me:x"], minute: 30, dm: true, space: true),
    ];

    test("by default: every room with a call, muted and low priority left out",
        () {
      expect(_calls(rooms, _card), ["fireside", "dm", "owls"]);
    });

    test("biggest calls first, then the longest running", () {
      expect(
          _calls(const [
            _R("late", ["@a:x"], minute: 50),
            _R("unknown", ["@a:x"]),
            _R("early", ["@a:x"], minute: 5),
          ], _card),
          ["early", "late", "unknown"]);
    });

    test("Include muted rooms brings back muted and low-priority rooms", () {
      expect(_calls(rooms, _card.copyWith(includeMuted: true)),
          ["fireside", "dm", "muted", "low", "owls"]);
    });

    test("direct-message calls can be left out", () {
      expect(_calls(rooms, _card.copyWith(dms: false)), ["fireside", "owls"]);
    });

    test("favorites only, or one space", () {
      expect(_calls(rooms, _card.copyWith(callsIn: HomeCard.callsInFavourites)),
          ["fireside"]);
      expect(_calls(rooms, _card.copyWith(callsIn: HomeCard.callsInSpace)),
          ["dm"]);
    });
  });

  group("Row lines", () {
    test("who's in the call", () {
      expect(callPeopleLine([]), "");
      expect(callPeopleLine(["Juni"]), "Juni");
      expect(callPeopleLine(["Juni", "Pell"]), "Juni and Pell");
      expect(callPeopleLine(["Juni", "Pell", "Hazel"]), "Juni, Pell and Hazel");
      expect(callPeopleLine(["Juni", "Pell", "Hazel", "Moss", "Fern"]),
          "Juni, Pell, Hazel and 2 more");
    });

    test("how long it has run", () {
      expect(callDurationLine(const Duration(seconds: 20)), "just started");
      expect(callDurationLine(const Duration(minutes: 6)), "6 min");
      expect(callDurationLine(const Duration(minutes: 60)), "1 h");
      expect(callDurationLine(const Duration(minutes: 72)), "1 h 12 min");
    });
  });

  group("The card's settings", () {
    test("defaults: all rooms, muted off, DMs on, no green dot", () {
      final card = const HomeLayout([]).newCard(HomeLayout.liveCalls);
      expect(card.callsIn, HomeCard.callsInAll);
      expect(card.includeMuted, isFalse);
      expect(card.dms, isTrue);
      expect(card.railDot, isFalse);
      expect(card.configurable, isTrue);
      expect(cardSummary(card), "All my rooms");
    });

    test("round-trip", () {
      final card = const HomeCard(HomeLayout.liveCalls).copyWith(
          callsIn: HomeCard.callsInSpace,
          space: "!s:x",
          spaceClient: "@me:x",
          includeMuted: true,
          dms: false,
          railDot: true);
      final json = card.toJson();
      expect(json["callsIn"], "space");
      expect(json["railDot"], true);
      expect(HomeCard.fromJson(json), card);
      expect(cardSummary(card),
          "One space · muted included · no DMs · green dot on Home");
    });

    test("an unknown callsIn reads as all rooms", () {
      expect(
          HomeCard.fromJson({"id": "live_calls", "callsIn": "planets"})!
              .callsIn,
          HomeCard.callsInAll);
    });

    test("library only: not on the default Overview; once per page", () {
      expect(HomeTabs.defaults.tabs.any((t) => t.holds(HomeLayout.liveCalls)),
          isFalse);
      expect(HomeLayout.knownTypes, contains(HomeLayout.liveCalls));
      expect(HomeLayout.multiTypes, isNot(contains(HomeLayout.liveCalls)));
      final layout =
          const HomeLayout([], inTab: true).add(HomeLayout.liveCalls);
      expect(layout.canAdd(HomeLayout.liveCalls), isFalse);
    });

    test("the side list's Live calls section", () {
      expect(HomeSection.knownTypes, contains(HomeSection.liveCalls));
      final lists = sideListRooms<String>(
        const [HomeSection(HomeSection.liveCalls)],
        ["call", "none"],
        SideListFacts(
          lastEvent: (r) => DateTime.utc(2026),
          isFavourite: (r) => false,
          isDirectMessage: (r) => false,
          isVoice: (r) => false,
          isLive: (r) => false,
          isPhotos: (r) => false,
          isStandalone: (r) => false,
          isLowPriority: (r) => false,
          spaceRooms: (s) => null,
          isInCall: (r) => r == "call",
        ),
      );
      expect(lists, [
        ["call"]
      ]);
    });
  });
}
