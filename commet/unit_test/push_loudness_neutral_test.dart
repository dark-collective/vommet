// Vommet issue 918: "All Messages" set on a room and "Threads I'm in" write
// rules that say "notify" without a sound. With the account's grid on
// Noisy, those messages notified silently once the rules were checked on
// the phone. Their sound now comes from the grid, in the app (RoomPushRules)
// and in the background service (PushRuleCheck) alike.
import 'package:commet/client/matrix/components/threads/thread_reply_rules.dart';
import 'package:commet/client/matrix/matrix_push_rules.dart';
import 'package:commet/utils/push_rule_check.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;

const _me = "@khan:example.org";
const _other = "@grin:example.org";
const _roomId = "!room:example.org";
const _root = r"$root";

const _sound = {"set_tweak": "sound", "value": "default"};
const _highlight = {"set_tweak": "highlight"};

const _noisy = ["notify", _sound];
const _on = ["notify"];
const _off = <Object?>[];

class _FakeSdkClient extends Fake implements matrix.Client {
  @override
  String? get userID => _me;
}

Map<String, Object?> _rule(
  String id,
  List<Object?> actions, {
  List<Object?> conditions = const [],
  bool isDefault = true,
}) {
  return {
    "rule_id": id,
    "default": isDefault,
    "enabled": true,
    "conditions": conditions,
    "actions": actions,
  };
}

Map<String, Object?> _match(String key, String pattern) {
  return {"kind": "event_match", "key": key, "pattern": pattern};
}

/// The group chat rule at [actions].
Map<String, Object?> _groupChats(List<Object?> actions) {
  final conditions = [_match("type", "m.room.message")];
  return _rule(".m.rule.message", actions, conditions: conditions);
}

/// The room's own "All Messages", as the room settings page writes it.
final _allMessages = _rule(_roomId, _on, isDefault: false);

/// "Only threads I'm in", with [_root] as a thread you're in.
List<Object?> _threads() {
  final inRoot = [
    _match("room_id", _roomId),
    _match(r"content.m\.relates_to.event_id", _root),
  ];
  final reply = [
    _match("type", "m.room.message"),
    _match(r"content.m\.relates_to.rel_type", "m.thread"),
  ];
  final threadId = ThreadReplyRules.threadId(_root);
  final muteId = ThreadReplyRules.globalMuteId;
  return [
    _rule(threadId, _on, isDefault: false, conditions: inRoot),
    _rule(muteId, _off, isDefault: false, conditions: reply),
  ];
}

matrix.PushRuleSet _rules({
  List<Object?> room = const [],
  List<Object?> group = _noisy,
  List<Object?> threads = const [],
}) {
  return matrix.PushRuleSet.fromJson({
    "override": const [],
    "content": const [],
    "room": room,
    "sender": const [],
    "underride": [...threads, _groupChats(group)],
  });
}

Map<String, Object?> _message({String? thread}) {
  final relation = {"rel_type": "m.thread", "event_id": thread};
  return {
    "type": "m.room.message",
    "sender": _other,
    "room_id": _roomId,
    "content": {
      "msgtype": "m.text",
      "body": "hi",
      if (thread != null) "m.relates_to": relation,
    },
  };
}

const _facts = PushRoomFacts(
  roomId: _roomId,
  ownUserId: _me,
  joinedMemberCount: 5,
);

/// What the app finds (RoomPushRules: the notification, desktop sounds and
/// the badge): (notify, sound).
(bool, bool) _app(matrix.PushRuleSet rules, Map<String, Object?> json) {
  final summary = {"m.joined_member_count": 5};
  final room = matrix.Room(
    id: _roomId,
    client: _FakeSdkClient(),
    summary: matrix.RoomSummary.fromJson(summary),
  );
  room.states[matrix.EventTypes.RoomMember] = {
    _me: matrix.StrippedStateEvent(
      type: matrix.EventTypes.RoomMember,
      senderId: _me,
      stateKey: _me,
      content: {"membership": "join", "displayname": "Khan"},
    ),
  };
  final event = matrix.Event.fromJson(
    {...json, "event_id": r"$event", "origin_server_ts": 1700000000000},
    room,
  );
  final action = RoomPushRules(rules).match(event);
  return (action.notify, action.sound != null);
}

/// What the background service finds (PushRuleCheck): (notify, sound).
(bool, bool) _background(matrix.PushRuleSet rules, Map<String, Object?> json) {
  final verdict = PushRuleCheck.evaluate(rules, json, _facts)!;
  return (verdict.notify, verdict.sound);
}

void main() {
  final paths = {"app": _app, "background": _background};

  for (final path in paths.entries) {
    final check = path.value;

    group(path.key, () {
      test("All Messages on the room plays the grid's sound", () {
        final rules = _rules(room: [_allMessages]);
        expect(check(rules, _message()), (true, true));
      });

      test("All Messages stays silent when group chats are On", () {
        final rules = _rules(room: [_allMessages], group: _on);
        expect(check(rules, _message()), (true, false));
      });

      test("All Messages still notifies when group chats are Off", () {
        final rules = _rules(room: [_allMessages], group: _off);
        expect(check(rules, _message()), (true, false));
      });

      test("a room rule with its own sound is kept", () {
        final own = _rule(_roomId, _noisy, isDefault: false);
        final rules = _rules(room: [own], group: _on);
        expect(check(rules, _message()), (true, true));
      });

      test("a muted room stays muted", () {
        final muted = _rule(_roomId, _off, isDefault: false);
        final rules = _rules(room: [muted]);
        expect(check(rules, _message()), (false, false));
      });

      test("group chats On stay silent without a rule of the room", () {
        final rules = _rules(group: _on);
        expect(check(rules, _message()), (true, false));
      });

      test("a reply in a thread you're in plays the grid's sound", () {
        final rules = _rules(threads: _threads());
        expect(check(rules, _message(thread: _root)), (true, true));
      });

      test("other thread replies stay muted", () {
        final rules = _rules(threads: _threads());
        final reply = _message(thread: r"$elsewhere");
        expect(check(rules, reply), (false, false));
      });
    });
  }

  test("the highlight is kept when the sound comes from the grid", () {
    final own = _rule(_roomId, ["notify", _highlight], isDefault: false);
    final rules = _rules(room: [own]);
    final verdict = PushRuleCheck.evaluate(rules, _message(), _facts)!;
    final result = [verdict.notify, verdict.sound, verdict.highlight];
    expect(result, [true, true, true]);
  });

  test("only rules of ours that say nothing about the sound are neutral", () {
    bool neutral(matrix.PushRuleKind kind, Object? json) {
      final rule = matrix.PushRule.fromJson(json as Map<String, Object?>);
      return MatrixPushRules.isLoudnessNeutral(kind, rule);
    }

    const room = matrix.PushRuleKind.room;
    const underride = matrix.PushRuleKind.underride;
    final noisyRoom = _rule(_roomId, _noisy, isDefault: false);
    final mutedRoom = _rule(_roomId, _off, isDefault: false);
    expect(neutral(room, _allMessages), isTrue);
    expect(neutral(room, noisyRoom), isFalse);
    expect(neutral(room, mutedRoom), isFalse);
    expect(neutral(underride, _threads().first), isTrue);
    expect(neutral(underride, _groupChats(_on)), isFalse);
    expect(MatrixPushRules.withoutLoudnessNeutralRules(_rules()), isNull);
  });
}
