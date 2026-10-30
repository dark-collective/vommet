import 'package:commet/client/matrix/matrix_default_push_rule.dart';
import 'package:commet/client/room.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:test/test.dart';

const me = "@me:example.org";

Map<String, Object?> member(String userId, String membership,
    {Map<String, Object?>? prev, Map<String, Object?>? extra, int ageMs = 0}) {
  return {
    "type": "m.room.member",
    "state_key": userId,
    "sender": userId,
    "event_id": "\$${userId.hashCode}-$membership-$ageMs",
    "origin_server_ts": now.millisecondsSinceEpoch - ageMs,
    "content": {"membership": membership, ...?extra},
    if (prev != null) "unsigned": {"prev_content": prev},
  };
}

final now = DateTime.fromMillisecondsSinceEpoch(1760000000000);

matrix.SyncUpdate sync(Map<String, List<Map<String, Object?>>> timelines,
    {Map<String, List<Map<String, Object?>>> states = const {}}) {
  return matrix.SyncUpdate.fromJson({
    "next_batch": "s1",
    "rooms": {
      "join": {
        for (final id in {...timelines.keys, ...states.keys})
          id: {
            if (timelines[id] != null) "timeline": {"events": timelines[id]},
            if (states[id] != null) "state": {"events": states[id]},
          }
      }
    }
  });
}

void main() {
  test("join after an invite counts as newly joined", () {
    final result = MatrixDefaultPushRule.findNewlyJoinedRooms(
        sync({
          "!a:x": [
            member(me, "join", prev: {"membership": "invite"})
          ]
        }),
        me,
        now);
    expect(result, {"!a:x": false});
  });

  test("join with no previous membership counts", () {
    final result = MatrixDefaultPushRule.findNewlyJoinedRooms(
        sync({}, states: {
          "!a:x": [member(me, "join")]
        }),
        me,
        now);
    expect(result, {"!a:x": false});
  });

  test("invite marked is_direct is reported as a direct chat", () {
    final result = MatrixDefaultPushRule.findNewlyJoinedRooms(
        sync({
          "!dm:x": [
            member(me, "join",
                prev: {"membership": "invite", "is_direct": true})
          ]
        }),
        me,
        now);
    expect(result, {"!dm:x": true});
  });

  test("profile change (join to join) is ignored", () {
    final result = MatrixDefaultPushRule.findNewlyJoinedRooms(
        sync({
          "!a:x": [
            member(me, "join",
                prev: {"membership": "join"}, extra: {"displayname": "Me"})
          ]
        }),
        me,
        now);
    expect(result, isEmpty);
  });

  test("other users joining are ignored", () {
    final result = MatrixDefaultPushRule.findNewlyJoinedRooms(
        sync({
          "!a:x": [member("@other:x", "join")]
        }),
        me,
        now);
    expect(result, isEmpty);
  });

  test("old joins (initial sync after login) are ignored", () {
    final result = MatrixDefaultPushRule.findNewlyJoinedRooms(
        sync({
          "!a:x": [
            member(me, "join",
                prev: {"membership": "invite"},
                ageMs: const Duration(days: 3).inMilliseconds)
          ]
        }),
        me,
        now);
    expect(result, isEmpty);
  });

  test("parse round-trips every level", () {
    for (final rule in PushRule.values) {
      expect(MatrixDefaultPushRule.parse(rule.name), rule);
    }
    expect(MatrixDefaultPushRule.parse(MatrixDefaultPushRule.accountDefault),
        isNull);
    expect(MatrixDefaultPushRule.parse("bogus"), isNull);
  });
}
