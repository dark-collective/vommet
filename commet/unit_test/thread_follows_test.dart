import 'dart:async';

import 'package:commet/client/matrix/components/threads/thread_follows.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;

// Vommet issue 1077: followed threads, saved in room account data.

/// Holds each room account data write until the test lets it finish.
class _Client extends Fake implements matrix.Client {
  final List<Completer<void>> writes = [];
  final List<Map<String, Object?>> sent = [];

  @override
  String? get userID => "@me:example.org";

  // No thread reply rules: follows don't touch push rules.
  @override
  matrix.PushRuleSet? get globalPushRules => null;

  @override
  Future<void> setAccountDataPerRoom(
    String userId,
    String roomId,
    String type,
    Map<String, Object?> content,
  ) {
    sent.add(content);
    final write = Completer<void>();
    writes.add(write);
    return write.future;
  }
}

Set<String> _followed(matrix.Room room) => {
      for (final MapEntry(:key, :value) in ThreadFollows.stored(room).entries)
        if (value.follow) key,
    };

void main() {
  const auto = ThreadFollowEntry(follow: true, ts: 100, automatic: r"$reply");
  const unfollowed = ThreadFollowEntry(follow: false, ts: 200);

  test("entries round-trip; broken ones are skipped", () {
    final content = ThreadFollows.withEntry(null, r"$a", auto);
    final parsed = ThreadFollows.parse(content);
    expect(parsed.keys, [r"$a"]);
    expect(parsed[r"$a"]!.follow, isTrue);
    expect(parsed[r"$a"]!.automatic, r"$reply");
    expect(parsed[r"$a"]!.ts, 100);
    expect(
      ThreadFollows.parse({
        "threads": {
          r"$x": {"follow": "yes", "ts": 1},
          r"$y": {"follow": false},
          r"$z": "nope",
        },
      }),
      isEmpty,
    );
    expect(ThreadFollows.parse(null), isEmpty);
    expect(ThreadFollows.parse({"threads": []}), isEmpty);
  });

  test("other keys in the content stay", () {
    final content = ThreadFollows.withEntry({"other": 1}, r"$a", unfollowed);
    expect(content["other"], 1);
  });

  test("only the newest entries are kept", () {
    Map<String, Object?>? content;
    for (var i = 0; i < ThreadFollows.maxPerRoom + 5; i++) {
      content = ThreadFollows.withEntry(
        content,
        "\$t$i",
        ThreadFollowEntry(follow: true, ts: i),
      );
    }
    final parsed = ThreadFollows.parse(content);
    expect(parsed.length, ThreadFollows.maxPerRoom);
    expect(parsed.containsKey(r"$t0"), isFalse);
    expect(parsed.containsKey("\$t${ThreadFollows.maxPerRoom + 4}"), isTrue);
  });

  test("an entry wins; without one you follow threads you're in", () {
    expect(
      ThreadFollows.decide(null, hasRule: false, startedOrParticipated: false),
      isFalse,
    );
    expect(
      ThreadFollows.decide(null, hasRule: false, startedOrParticipated: true),
      isTrue,
    );
    expect(
      ThreadFollows.decide(null, hasRule: true, startedOrParticipated: false),
      isTrue,
      reason: "a mention's thread rule from before follows still count",
    );
    expect(
      ThreadFollows.decide(
        unfollowed,
        hasRule: true,
        startedOrParticipated: true,
      ),
      isFalse,
      reason: "an unfollow wins over replying earlier",
    );
    expect(
      ThreadFollows.decide(
        const ThreadFollowEntry(follow: true, ts: 1),
        hasRule: false,
        startedOrParticipated: false,
      ),
      isTrue,
      reason: "followed by hand",
    );
  });

  test("an unfollow sticks until you reply again", () {
    expect(
      ThreadFollows.autoFollowApplies(null, ownReply: false, eventTs: 1),
      isTrue,
    );
    expect(
      ThreadFollows.autoFollowApplies(
        unfollowed,
        ownReply: false,
        eventTs: 999,
      ),
      isFalse,
      reason: "a mention doesn't follow it again",
    );
    expect(
      ThreadFollows.autoFollowApplies(unfollowed, ownReply: true, eventTs: 150),
      isFalse,
      reason: "a reply from before the unfollow doesn't count",
    );
    expect(
      ThreadFollows.autoFollowApplies(unfollowed, ownReply: true, eventTs: 300),
      isTrue,
    );
  });

  test("overlapping follows in a room keep each other", () async {
    final client = _Client();
    final room = matrix.Room(id: "!room:example.org", client: client);
    final first = ThreadFollows.set(room, r"$a", true);
    final second = ThreadFollows.set(room, r"$b", true);
    await pumpEventQueue();
    // Shown before the server has it; the second write waits for the first.
    expect(_followed(room), {r"$a"});
    expect(client.sent.length, 1);
    client.writes[0].complete();
    await first;
    await pumpEventQueue();
    expect(client.sent.length, 2);
    expect(ThreadFollows.parse(client.sent[1]).keys.toSet(), {r"$a", r"$b"});
    client.writes[1].complete();
    await second;
    expect(_followed(room), {r"$a", r"$b"});
  });

  test("a failed write is undone", () async {
    final client = _Client();
    final room = matrix.Room(id: "!room:example.org", client: client);
    final failing = ThreadFollows.set(room, r"$a", true);
    await pumpEventQueue();
    expect(_followed(room), {r"$a"});
    client.writes[0].completeError(StateError("offline"));
    await expectLater(failing, throwsStateError);
    expect(_followed(room), isEmpty);
  });

  test("the write after a failed one still runs, without it", () async {
    final client = _Client();
    final room = matrix.Room(id: "!room:example.org", client: client);
    final failing = ThreadFollows.set(room, r"$a", true);
    final next = ThreadFollows.set(room, r"$b", true);
    await pumpEventQueue();
    // The second write waits for the first.
    expect(client.sent, hasLength(1));
    client.writes[0].completeError(StateError("offline"));
    await expectLater(failing, throwsStateError);
    await pumpEventQueue();
    expect(ThreadFollows.parse(client.sent[1]).keys.toSet(), {r"$b"});
    client.writes[1].complete();
    await next;
    expect(_followed(room), {r"$b"});
  });

  test("followed roots across rooms, newest first", () {
    expect(
      ThreadFollows.followedRoots({
        "!a": {
          r"$old": const ThreadFollowEntry(follow: true, ts: 1),
          r"$gone": const ThreadFollowEntry(follow: false, ts: 9),
        },
        "!b": {r"$new": const ThreadFollowEntry(follow: true, ts: 5)},
      }),
      [(roomId: "!b", rootId: r"$new"), (roomId: "!a", rootId: r"$old")],
    );
  });

  test("a thread's last activity is its latest reply's time", () {
    final room = matrix.Room(id: "!room:example.org", client: _Client());
    Map<String, Object?> rootJson(Map<String, Object?>? latest) => {
          "type": "m.room.message",
          "event_id": r"$root",
          "room_id": room.id,
          "sender": "@other:example.org",
          "origin_server_ts": 1000,
          "content": {"msgtype": "m.text", "body": "hi"},
          if (latest != null)
            "unsigned": {
              "m.relations": {
                "m.thread": {"count": 1, "latest_event": latest},
              },
            },
        };
    expect(
      ThreadFollows.lastActivityOf(
        matrix.Event.fromJson(rootJson({"origin_server_ts": 5000}), room),
      ),
      5000,
    );
    expect(
      ThreadFollows.lastActivityOf(matrix.Event.fromJson(rootJson(null), room)),
      1000,
    );
  });

  test("threads you're in without an entry join the rules, unfollowed don't",
      () {
    expect(
      ThreadFollows.followedRoots(
        {
          "!a": {
            r"$hand": const ThreadFollowEntry(follow: true, ts: 3),
            r"$left": const ThreadFollowEntry(follow: false, ts: 9),
          },
        },
        byDefault: {
          "!a": [
            (rootId: r"$mine", ts: 7),
            (rootId: r"$left", ts: 8),
            (rootId: r"$hand", ts: 1),
          ],
          "!b": [(rootId: r"$other", ts: 2)],
        },
      ),
      [
        (roomId: "!a", rootId: r"$mine"),
        (roomId: "!a", rootId: r"$hand"),
        (roomId: "!b", rootId: r"$other"),
      ],
    );
  });
}
