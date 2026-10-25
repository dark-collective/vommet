import 'package:commet/client/client.dart';
import 'package:commet/client/components/activities/activities_component.dart';
import 'package:commet/client/components/friends/friends_component.dart';
import 'package:commet/client/components/room_component.dart';
import 'package:commet/client/components/user_presence/user_presence_component.dart';
import 'package:commet/ui/organisms/friends/friends_model.dart';
import 'package:commet/utils/image_or_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Activities implements ActivitiesComponent {
  _Activities(this.sessions);
  final List<RoomActivitySession> sessions;
  @override
  List<RoomActivitySession> getSessions() => sessions;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Room implements Room {
  _Room(this.identifier, List<RoomActivitySession> sessions)
      : activities = _Activities(sessions);
  @override
  final String identifier;
  final _Activities activities;
  @override
  T? getComponent<T extends RoomComponent>() =>
      activities is T ? activities as T : null;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

RoomActivitySession _session(Set<String> people, {bool thirdparty = false}) =>
    RoomActivitySession(
        participants: people,
        application: thirdparty ? "Watch Together" : "m.call",
        thirdparty: thirdparty,
        icon: ImageOrIcon(icon: Icons.call));

void main() {
  group("FriendsListContent", () {
    test("parses only Matrix IDs", () {
      expect(
          FriendsListContent.parse({
            "friends": {
              "@a:x": {"added_ts": 1},
              "nope": {},
              "@b:y": {},
            }
          }),
          {"@a:x", "@b:y"});
      expect(FriendsListContent.parse(null), isEmpty);
      expect(FriendsListContent.parse({"friends": []}), isEmpty);
    });

    test("adding keeps the first added_ts and other fields", () {
      var content = FriendsListContent.withFriends({
        "other": 1,
        "friends": {
          "@a:x": {"added_ts": 5}
        }
      }, [
        "@a:x",
        "@b:x"
      ], 9);
      expect(content["other"], 1);
      expect(content["friends"]["@a:x"]["added_ts"], 5);
      expect(content["friends"]["@b:x"]["added_ts"], 9);
      content = FriendsListContent.without(content, "@a:x");
      expect(FriendsListContent.parse(content), {"@b:x"});
    });
  });

  group("FriendsListContent linked accounts (Vommet issue 638)", () {
    Map<String, dynamic> list(Map<String, dynamic> friends) =>
        {"friends": friends};

    test("plain entries are no people", () {
      expect(
          FriendsListContent.people(list({
            "@a:x": {"added_ts": 1},
            "@b:y": {"added_ts": 2},
          })),
          isEmpty);
    });

    test("linking makes one person with the main account first", () {
      var c = list({
        "@a:x": {"added_ts": 1},
        "@b:y": {"added_ts": 2},
        "@c:z": {"added_ts": 3},
      });
      c = FriendsListContent.linked(c, "@b:y", "@a:x", 10);
      expect(FriendsListContent.people(c), [
        ["@b:y", "@a:x"]
      ]);
      // Linking a third account joins the same person.
      c = FriendsListContent.linked(c, "@b:y", "@c:z", 11);
      expect(FriendsListContent.people(c), [
        ["@b:y", "@a:x", "@c:z"]
      ]);
      expect(FriendsListContent.parse(c), {"@a:x", "@b:y", "@c:z"});
    });

    test("linking a new ID adds it to the list", () {
      final c = FriendsListContent.linked(
          list({
            "@a:x": {"added_ts": 1}
          }),
          "@a:x",
          "@a:other.org",
          7);
      expect(c["friends"]["@a:other.org"]["added_ts"], 7);
      expect(FriendsListContent.people(c), [
        ["@a:x", "@a:other.org"]
      ]);
    });

    test("linking someone already linked brings their whole person", () {
      var c = list({
        "@a:x": {},
        "@b:x": {},
        "@c:x": {},
        "@d:x": {},
      });
      c = FriendsListContent.linked(c, "@a:x", "@b:x", 1);
      c = FriendsListContent.linked(c, "@c:x", "@d:x", 2);
      c = FriendsListContent.linked(c, "@a:x", "@d:x", 3);
      expect(FriendsListContent.people(c).single.toSet(),
          {"@a:x", "@b:x", "@c:x", "@d:x"});
      expect(FriendsListContent.people(c).single.first, "@a:x");
    });

    test("make main and unlink", () {
      var c = list({
        "@a:x": {"added_ts": 1},
        "@b:y": {"added_ts": 2},
        "@c:z": {"added_ts": 3},
      });
      c = FriendsListContent.linked(c, "@a:x", "@b:y", 10);
      c = FriendsListContent.linked(c, "@a:x", "@c:z", 11);
      c = FriendsListContent.withMain(c, "@c:z");
      expect(FriendsListContent.people(c).single.first, "@c:z");
      // Unlinking the main account falls back to the earliest added.
      c = FriendsListContent.unlinked(c, "@c:z");
      expect(FriendsListContent.people(c), [
        ["@a:x", "@b:y"]
      ]);
      expect(c["friends"]["@c:z"].containsKey("person"), isFalse);
      // A person left with one account is a plain entry again.
      c = FriendsListContent.unlinked(c, "@b:y");
      expect(FriendsListContent.people(c), isEmpty);
      expect(c["friends"]["@a:x"].containsKey("person"), isFalse);
      expect(c["friends"]["@a:x"]["added_ts"], 1);
    });

    test("an unlinked account can start a new person of its own", () {
      var c = list({"@a:x": {}, "@b:x": {}, "@c:x": {}});
      c = FriendsListContent.linked(c, "@a:x", "@b:x", 1);
      c = FriendsListContent.unlinked(c, "@a:x");
      c = FriendsListContent.linked(c, "@a:x", "@c:x", 2);
      expect(FriendsListContent.people(c), [
        ["@a:x", "@c:x"]
      ]);
    });

    test("removing all accounts of a person", () {
      var c = list({"@a:x": {}, "@b:x": {}, "@c:x": {}});
      c = FriendsListContent.linked(c, "@a:x", "@b:x", 1);
      c = FriendsListContent.withoutAll(c, ["@a:x", "@b:x"]);
      expect(FriendsListContent.parse(c), {"@c:x"});
    });
  });

  group("FriendsModel linked accounts (Vommet issue 638)", () {
    test("the most active account wins, the main one on a tie", () {
      final accounts = [
        ("main", UserPresenceStatus.offline),
        ("alt", UserPresenceStatus.unavailable),
        ("alt2", UserPresenceStatus.online),
      ];
      expect(FriendsModel.mostActive(accounts, (a) => a.$2).$1, "alt2");
      expect(
          FriendsModel.mostActive([
            ("main", UserPresenceStatus.online),
            ("alt", UserPresenceStatus.online),
          ], (a) => a.$2).$1,
          "main");
      expect(
          FriendsModel.mostActive([
            ("main", UserPresenceStatus.offline),
            ("alt", UserPresenceStatus.unknown),
          ], (a) => a.$2).$1,
          "alt");
    });

    test("main keys map each linked account to its main", () {
      expect(
          FriendsModel.mainKeys("me", [
            ["@a:x", "@a:y", "@a:z"]
          ]),
          {"me|@a:y": "me|@a:x", "me|@a:z": "me|@a:x"});
    });

    test("the Message sheet lists DMs first, most recent first", () {
      expect(
          FriendsModel.dmPickOrder([
            "@a:x",
            "@a:y",
            "@a:z"
          ], {
            "@a:z": DateTime(2026, 10, 1),
            "@a:y": DateTime(2026, 10, 20),
          }),
          ["@a:y", "@a:z", "@a:x"]);
    });

    test("a DM opens on the active account, else the last active one", () {
      final dms = {
        "work": DateTime(2026, 10, 1),
        "home": DateTime(2026, 10, 20),
        "old": DateTime(2026, 9, 1),
      };
      expect(FriendsModel.dmAccount("work", dms), "work");
      expect(FriendsModel.dmAccount("phone", dms), "home");
      expect(FriendsModel.dmAccount("phone", <String, DateTime>{}), isNull);
    });
  });

  group("FriendsModel.activeNow", () {
    test("only calls with a friend, friends first, without you", () {
      final rooms = [
        _Room("!strangers", [
          _session({"@s:x", "@t:x"})
        ]),
        _Room("!fireside", [
          _session({"@me:x", "@zed:x", "@juni:x", "@pell:x"})
        ]),
        _Room("!dm", [
          _session({"@mossy:x"})
        ]),
        _Room("!watch", [
          _session({"@juni:x"}, thirdparty: true)
        ]),
      ];
      final calls = FriendsModel.activeNow(
          rooms, {"@juni:x", "@pell:x", "@mossy:x"}, "@me:x");
      expect(calls.map((c) => c.room.identifier), ["!fireside", "!dm"]);
      expect(calls.first.friendsIn, ["@juni:x", "@pell:x"]);
      expect(calls.first.participants, ["@juni:x", "@pell:x", "@zed:x"]);
    });

    test("no friends, no calls", () {
      expect(
          FriendsModel.activeNow([
            _Room("!r", [
              _session({"@a:x"})
            ])
          ], {}, "@me:x"),
          isEmpty);
    });
  });

  test("suggestions skip friends and yourself", () {
    expect(
        FriendsModel.suggestions(
            ["@b:x", "@a:x", "@me:x", "@b:x", "@f:x"], {"@f:x"}, "@me:x"),
        ["@a:x", "@b:x"]);
  });

  test("isUserId", () {
    expect(FriendsModel.isUserId(" @a:x.org "), isTrue);
    expect(FriendsModel.isUserId("@a"), isFalse);
    expect(FriendsModel.isUserId("a:x"), isFalse);
    expect(FriendsModel.isUserId("@:x"), isFalse);
    expect(FriendsModel.isUserId("@a b:x"), isFalse);
  });

  test("friends sort online/away, then unknown, then offline, by name", () {
    final friends = [
      ("dana", UserPresenceStatus.offline),
      ("Bea", UserPresenceStatus.unknown),
      ("carl", UserPresenceStatus.online),
      ("Ada", UserPresenceStatus.unknown),
      ("Eve", UserPresenceStatus.unavailable),
      ("abe", UserPresenceStatus.offline),
    ]..sort((a, b) => FriendsModel.compareFriends(a.$2, a.$1, b.$2, b.$1));
    expect(
        friends.map((f) => f.$1), ["carl", "Eve", "Ada", "Bea", "abe", "dana"]);
  });

  group("Add friend lookup", () {
    const dms = {
      "@mustapha:nether.im": "Mustapha Mond",
      "@bernard:x.org": "Bernard",
      "@lenina:nether.im": "Lenina Crowne",
      "@me:nether.im": "Me",
    };
    List<String> ids(List<FriendCandidate> c) => [for (final x in c) x.userId];

    test("DM partners come before directory hits", () {
      final rows = FriendsModel.lookup("mus",
          dmPartners: dms,
          directory: [
            ("@mustaphamond:matrix.org", "Mustapha"),
            ("@mustapha:nether.im", "Mustapha Mond"),
          ],
          friends: {},
          selfId: "@me:nether.im");
      expect(ids(rows), ["@mustapha:nether.im", "@mustaphamond:matrix.org"]);
      expect(rows.first.fromDm, isTrue);
      expect(rows.last.fromDm, isFalse);
    });

    test("a typed ID prefix and a bare '@name:' both match", () {
      for (final q in ["@lenina:", "@len", "crowne"]) {
        expect(
            ids(FriendsModel.lookup(q,
                dmPartners: dms, directory: [], friends: {})),
            ["@lenina:nether.im"],
            reason: q);
      }
      expect(FriendsModel.directoryTerm(" @lenina: "), "lenina");
    });

    test("better matches first, friends marked, yourself left out", () {
      final rows = FriendsModel.lookup("me",
          dmPartners: {
            ...dms,
            "@homer:x.org": "Homer",
            "@meg:x.org": "Meg",
          },
          directory: [],
          friends: {"@meg:x.org"},
          selfId: "@me:nether.im");
      expect(ids(rows), ["@meg:x.org", "@homer:x.org"]);
      expect(rows.first.alreadyFriend, isTrue);
    });

    test("a directory hit you have a DM with counts as a DM", () {
      final rows = FriendsModel.lookup("bernie", dmPartners: dms, directory: [
        ("@other:y.org", "Bernie"),
        ("@bernard:x.org", "Bernie M"),
      ], friends: {});
      expect(ids(rows), ["@bernard:x.org", "@other:y.org"]);
      expect(rows.first.name, "Bernard");
    });

    test("empty query lists DM partners not yet friends", () {
      final rows = FriendsModel.lookup("",
          dmPartners: dms,
          directory: [("@z:z", "Z")],
          friends: {"@bernard:x.org"},
          selfId: "@me:nether.im");
      expect(ids(rows), ["@lenina:nether.im", "@mustapha:nether.im"]);
    });
  });
}
