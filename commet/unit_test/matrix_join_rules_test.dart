import 'package:commet/client/matrix/matrix_join_rules.dart';
import 'package:commet/client/room.dart';
import 'package:test/test.dart';

void main() {
  group("join rule -> visibility", () {
    test("knock shows as Ask to join, not private", () {
      expect(roomVisibilityFromJoinRule("knock"), RoomVisibilityKnock([]));
      expect(roomVisibilityFromJoinRule("knock") is RoomVisibilityPrivate,
          isFalse);
    });

    test("knock_restricted keeps its spaces", () {
      expect(roomVisibilityFromJoinRule("knock_restricted", allow: ["!s:x"]),
          RoomVisibilityKnock(["!s:x"]));
    });

    test("other rules unchanged", () {
      expect(roomVisibilityFromJoinRule("public"), RoomVisibilityPublic());
      expect(roomVisibilityFromJoinRule(null), RoomVisibilityPublic());
      expect(roomVisibilityFromJoinRule("invite"), RoomVisibilityPrivate());
      expect(roomVisibilityFromJoinRule("private"), RoomVisibilityPrivate());
      expect(roomVisibilityFromJoinRule("something"), RoomVisibilityPrivate());
      expect(roomVisibilityFromJoinRule("restricted", allow: ["!a:x"]),
          RoomVisibilityRestricted(["!a:x"]));
    });
  });

  group("visibility -> join rules content", () {
    test("knock", () {
      expect(joinRuleContent(RoomVisibilityKnock([])), {"join_rule": "knock"});
    });

    test("knock with spaces is knock_restricted", () {
      expect(joinRuleContent(RoomVisibilityKnock(["!s:x"])), {
        "join_rule": "knock_restricted",
        "allow": [
          {"room_id": "!s:x", "type": "m.room_membership"}
        ],
      });
    });

    test("private, public, restricted", () {
      expect(joinRuleContent(RoomVisibilityPrivate()), {"join_rule": "invite"});
      expect(joinRuleContent(RoomVisibilityPublic()), {"join_rule": "public"});
      expect(joinRuleContent(RoomVisibilityRestricted(["!a:x"])), {
        "join_rule": "restricted",
        "allow": [
          {"room_id": "!a:x", "type": "m.room_membership"}
        ],
      });
    });

    test("round trip", () {
      for (final v in [
        RoomVisibilityPublic(),
        RoomVisibilityPrivate(),
        RoomVisibilityKnock([]),
        RoomVisibilityKnock(["!s:x"]),
        RoomVisibilityRestricted(["!a:x", "!b:x"]),
      ]) {
        final content = joinRuleContent(v);
        expect(
            roomVisibilityFromJoinRule(content["join_rule"] as String,
                allow: joinRuleAllowedRooms(content)),
            v);
      }
    });
  });

  test("allow list parsing skips malformed entries", () {
    expect(
        joinRuleAllowedRooms({
          "allow": [
            {"room_id": "!a:x", "type": "m.room_membership"},
            {"type": "m.room_membership"},
            "junk",
          ]
        }),
        ["!a:x"]);
    expect(joinRuleAllowedRooms(null), isEmpty);
  });

  test("room versions that support knocking", () {
    expect(roomVersionSupportsKnock(null), isFalse);
    expect(roomVersionSupportsKnock("6"), isFalse);
    expect(roomVersionSupportsKnock("7"), isTrue);
    expect(roomVersionSupportsKnock("12"), isTrue);
    expect(roomVersionSupportsKnock("org.example.custom"), isFalse);
    expect(roomVersionSupportsKnockRestricted("9"), isFalse);
    expect(roomVersionSupportsKnockRestricted("10"), isTrue);
  });
}
