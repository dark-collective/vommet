import 'package:commet/client/matrix/components/threads/thread_reply_rules.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;

// Vommet issue 785: "Thread replies notify me" as server push rules.

const _me = "@khan:example.org";
const _roomId = "!room:example.org";
const _otherRoom = "!other:example.org";

class _FakeSdkClient extends Fake implements matrix.Client {
  @override
  String? get userID => _me;
}

/// The account's underride rules as a homeserver keeps them: a new rule
/// goes first unless `before`/`after` name another user rule, and the
/// server-default `.m.rule.message` stays last.
class _Server {
  final List<matrix.PushRule> user = [
    matrix.PushRule(
        ruleId: "someone.elses",
        default$: false,
        enabled: true,
        actions: [
          "notify"
        ],
        conditions: [
          matrix.PushCondition(
              kind: "event_match", key: "type", pattern: "org.example.ping")
        ]),
  ];
  final List<String> calls = [];

  matrix.PushRuleSet get rules => matrix.PushRuleSet(
        override: [],
        content: [
          matrix.PushRule(
              ruleId: "keyword",
              default$: false,
              enabled: true,
              pattern: "lasagna",
              actions: ["notify"]),
        ],
        room: [],
        sender: [],
        underride: [
          ...user,
          matrix.PushRule(
              ruleId: ".m.rule.message",
              default$: true,
              enabled: true,
              actions: [
                "notify"
              ],
              conditions: [
                matrix.PushCondition(
                    kind: "event_match", key: "type", pattern: "m.room.message")
              ]),
        ],
      );

  Future<void> put(String ruleId, List<Object> actions,
      List<matrix.PushCondition> conditions,
      {String? before, String? after}) async {
    calls.add("put $ruleId");
    final rule = matrix.PushRule(
        ruleId: ruleId,
        default$: false,
        enabled: true,
        actions: actions,
        conditions: conditions);
    final existing = user.indexWhere((r) => r.ruleId == ruleId);
    if (existing >= 0) user.removeAt(existing);
    int at = 0;
    if (before != null) {
      at = user.indexWhere((r) => r.ruleId == before);
      expect(at, isNonNegative, reason: "before $before");
    } else if (after != null) {
      at = user.indexWhere((r) => r.ruleId == after) + 1;
      expect(at, isPositive, reason: "after $after");
    }
    user.insert(at, rule);
  }

  Future<void> delete(String ruleId) async {
    calls.add("delete $ruleId");
    final i = user.indexWhere((r) => r.ruleId == ruleId);
    expect(i, isNonNegative, reason: "delete $ruleId");
    user.removeAt(i);
  }

  Future<void> account(ThreadReplyNotify choice) =>
      ThreadReplyRules.setAccountChoice(rules, choice,
          put: put, delete: delete);

  Future<void> room(String roomId, ThreadReplyNotify? choice) =>
      ThreadReplyRules.setRoomChoice(rules, roomId, choice,
          put: put, delete: delete);

  Future<bool> thread(String roomId, String rootId) =>
      ThreadReplyRules.addThread(rules, roomId, rootId,
          put: put, delete: delete);

  bool notifies(matrix.Event event) =>
      matrix.PushruleEvaluator.fromRuleset(rules).match(event).notify;

  List<String> get ours => [
        for (final r in user)
          if (r.ruleId.startsWith(ThreadReplyRules.prefix)) r.ruleId
      ];
}

matrix.Event _event(String body,
    {String? threadRoot, String roomId = _roomId, String id = "\$e"}) {
  final room = matrix.Room(id: roomId, client: _FakeSdkClient());
  return matrix.Event.fromJson({
    "type": matrix.EventTypes.Message,
    "event_id": id,
    "room_id": roomId,
    "sender": "@grin:example.org",
    "origin_server_ts": 1700000000000,
    "content": {
      "msgtype": "m.text",
      "body": body,
      if (threadRoot != null)
        "m.relates_to": {"rel_type": "m.thread", "event_id": threadRoot},
    },
  }, room);
}

void main() {
  test(
      "account choice mutes other threads; keywords and the main timeline "
      "still notify", () async {
    final s = _Server();
    expect(ThreadReplyRules.accountChoice(s.rules), ThreadReplyNotify.all);
    expect(s.notifies(_event("hi", threadRoot: "\$root")), isTrue);

    await s.account(ThreadReplyNotify.mine);
    expect(ThreadReplyRules.accountChoice(s.rules), ThreadReplyNotify.mine);
    expect(s.notifies(_event("hi", threadRoot: "\$root")), isFalse);
    expect(s.notifies(_event("hi")), isTrue);
    expect(s.notifies(_event("lasagna time", threadRoot: "\$root")), isTrue);
  });

  test("setting it twice changes nothing; All threads removes every rule",
      () async {
    final s = _Server();
    await s.account(ThreadReplyNotify.mine);
    await s.account(ThreadReplyNotify.mine);
    expect(s.calls, ["put ${ThreadReplyRules.globalMuteId}"]);
    expect(await s.thread(_roomId, "\$root"), isTrue);
    expect(await s.thread(_roomId, "\$root"), isFalse);

    await s.account(ThreadReplyNotify.all);
    expect(s.ours, isEmpty);
    expect(s.user.map((r) => r.ruleId), ["someone.elses"]);
    await s.account(ThreadReplyNotify.all);
    expect(s.calls.where((c) => c.startsWith("put")).length, 2);
  });

  test("a thread you're in keeps notifying, whatever order rules come in",
      () async {
    final s = _Server();
    await s.account(ThreadReplyNotify.mine);
    await s.thread(_roomId, "\$root");
    await s.room(_otherRoom, ThreadReplyNotify.mine);
    await s.thread(_roomId, "\$second");
    expect(s.notifies(_event("hi", threadRoot: "\$root")), isTrue);
    expect(s.notifies(_event("hi", threadRoot: "\$second")), isTrue);
    expect(s.notifies(_event("hi", threadRoot: "\$third")), isFalse);
    // Thread rules sit above every mute rule, newest first.
    expect(s.ours, [
      ThreadReplyRules.threadId("\$second"),
      ThreadReplyRules.threadId("\$root"),
      ThreadReplyRules.globalMuteId,
      ThreadReplyRules.roomMuteId(_otherRoom),
    ]);
  });

  test("threads aren't added where replies notify anyway", () async {
    final s = _Server();
    expect(await s.thread(_roomId, "\$root"), isFalse);
    await s.account(ThreadReplyNotify.mine);
    await s.room(_otherRoom, ThreadReplyNotify.all);
    expect(await s.thread(_otherRoom, "\$root"), isFalse);
    expect(s.notifies(_event("hi", threadRoot: "\$x", roomId: _otherRoom)),
        isTrue);
  });

  test("a room's own choice overrides the account's and goes back to default",
      () async {
    final s = _Server();
    await s.room(_roomId, ThreadReplyNotify.mine);
    expect(
        ThreadReplyRules.roomChoice(s.rules, _roomId), ThreadReplyNotify.mine);
    expect(s.notifies(_event("hi", threadRoot: "\$r")), isFalse);
    expect(s.notifies(_event("hi", threadRoot: "\$r", roomId: _otherRoom)),
        isTrue);
    await s.thread(_roomId, "\$r");
    expect(s.notifies(_event("hi", threadRoot: "\$r")), isTrue);

    await s.room(_roomId, ThreadReplyNotify.all);
    expect(
        ThreadReplyRules.roomChoice(s.rules, _roomId), ThreadReplyNotify.all);
    // No mute left: the thread rule went with it.
    expect(s.ours, [ThreadReplyRules.roomAllId(_roomId)]);

    await s.room(_roomId, null);
    expect(ThreadReplyRules.roomChoice(s.rules, _roomId), isNull);
    expect(s.ours, isEmpty);
    expect(s.user.map((r) => r.ruleId), ["someone.elses"]);
  });

  test("the oldest threads are dropped past the limit", () async {
    final s = _Server();
    await s.account(ThreadReplyNotify.mine);
    for (var i = 0; i <= ThreadReplyRules.maxThreads; i++) {
      await s.thread(_roomId, "\$t$i");
    }
    final threads = s.ours.where((id) => id.contains(".in.")).toList();
    expect(threads.length, ThreadReplyRules.maxThreads);
    expect(threads.first,
        ThreadReplyRules.threadId("\$t${ThreadReplyRules.maxThreads}"));
    expect(threads, isNot(contains(ThreadReplyRules.threadId("\$t0"))));
  });

  test("rule ids have no slashes", () {
    expect(ThreadReplyRules.threadId("\$ab/c+d"),
        "${ThreadReplyRules.prefix}in.\$ab_c+d");
  });
}
