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
}
