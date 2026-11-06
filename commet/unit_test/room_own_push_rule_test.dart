// Vommet: a room's settings page offers "Use default (…)" (removes the
// room's own rules) and explicit levels that always write a rule of the
// room's own, so "set here" and "default" stay apart.
import 'package:commet/client/matrix/room_own_push_rule.dart';
import 'package:commet/client/room.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;

const _me = "@khan:example.org";
const _roomId = "!room:example.org";

class _FakeSdkClient extends Fake implements matrix.Client {
  _FakeSdkClient(this.rules);
  final matrix.PushRuleSet rules;

  @override
  String? get userID => _me;

  @override
  matrix.PushRuleSet? get globalPushRules => rules;
}

Map<String, Object?> _rule(String id, List<Object?> actions,
        {List<Map<String, Object?>>? conditions, bool isDefault = false}) =>
    {
      "rule_id": id,
      "default": isDefault,
      "enabled": true,
      "actions": actions,
      if (conditions != null) "conditions": conditions,
    };

/// The default group-chat rule, notifying or not ("Group chats: Off").
Map<String, Object?> _groupMessages({required bool notify}) =>
    _rule(".m.rule.message", notify ? ["notify"] : [],
        conditions: [
          {"kind": "event_match", "key": "type", "pattern": "m.room.message"}
        ],
        isDefault: true);

Map<String, Object?> _mute(String roomId) => _rule(roomId, [], conditions: [
      {"kind": "event_match", "key": "room_id", "pattern": roomId}
    ]);

matrix.PushRuleSet _rules({
  List<Map<String, Object?>> override = const [],
  List<Map<String, Object?>> room = const [],
  bool groupNotifies = true,
}) =>
    matrix.PushRuleSet.fromJson({
      "override": override,
      "content": [],
      "room": room,
      "sender": [],
      "underride": [_groupMessages(notify: groupNotifies)],
    });

/// An ordinary message from someone else (as MatrixRoom's probe).
matrix.Event _probe(matrix.PushRuleSet rules) {
  final room = matrix.Room(id: _roomId, client: _FakeSdkClient(rules));
  return matrix.Event(
    type: matrix.EventTypes.Message,
    content: {"msgtype": "m.text", "body": ""},
    senderId: "@vommet-probe:invalid",
    eventId: "\$vommet-probe",
    room: room,
    originServerTs: DateTime.now(),
  );
}

/// Records the calls [RoomOwnPushRule] makes.
class _Calls {
  final List<String> log = [];

  Future<void> delete(matrix.PushRuleKind kind, String ruleId) async =>
      log.add("delete ${kind.name} $ruleId");

  Future<void> put(
      matrix.PushRuleKind kind, String ruleId, List<Object> actions,
      {List<matrix.PushCondition>? conditions}) async {
    final room =
        conditions?.map((c) => "${c.kind}:${c.key}=${c.pattern}").join(",");
    log.add("put ${kind.name} $ruleId $actions${room == null ? "" : " $room"}");
  }
}

void main() {
  group("hasOwnRule", () {
    test("no rule of its own", () {
      expect(RoomOwnPushRule.hasOwnRule(_rules(), _roomId), false);
      expect(RoomOwnPushRule.hasOwnRule(null, _roomId), false);
    });

    test("a mute, a mentions rule or a notify rule are its own", () {
      expect(
          RoomOwnPushRule.hasOwnRule(
              _rules(override: [_mute(_roomId)]), _roomId),
          true);
      expect(
          RoomOwnPushRule.hasOwnRule(
              _rules(room: [_rule(_roomId, [])]), _roomId),
          true);
      expect(
          RoomOwnPushRule.hasOwnRule(
              _rules(room: [
                _rule(_roomId, ["notify"])
              ]),
              _roomId),
          true);
    });

    test("another room's rule is not", () {
      expect(
          RoomOwnPushRule.hasOwnRule(
              _rules(room: [_rule("!other:example.org", [])]), _roomId),
          false);
    });
  });

  group("defaultLevel", () {
    test("All Messages where group chats notify", () {
      final rules = _rules();
      expect(
          RoomOwnPushRule.defaultLevel(rules, _probe(rules)), PushRule.notify);
    });

    test("Mentions & Keywords where group chats are off", () {
      final rules = _rules(groupNotifies: false);
      expect(RoomOwnPushRule.defaultLevel(rules, _probe(rules)),
          PushRule.mentionsOnly);
    });

    test("ignores the room's own rules", () {
      final muted = _rules(override: [_mute(_roomId)]);
      expect(
          RoomOwnPushRule.defaultLevel(muted, _probe(muted)), PushRule.notify);

      final pinned = _rules(groupNotifies: false, room: [
        _rule(_roomId, ["notify"])
      ]);
      expect(RoomOwnPushRule.defaultLevel(pinned, _probe(pinned)),
          PushRule.mentionsOnly);
    });
  });

  group("clear (Use default)", () {
    test("removes the room's mute and room rule", () async {
      final calls = _Calls();
      await RoomOwnPushRule.clear(
          _rules(override: [_mute(_roomId)], room: [_rule(_roomId, [])]),
          _roomId,
          delete: calls.delete);
      expect(calls.log, ["delete override $_roomId", "delete room $_roomId"]);
    });

    test("removes an explicit All Messages rule", () async {
      final calls = _Calls();
      await RoomOwnPushRule.clear(
          _rules(room: [
            _rule(_roomId, ["notify"])
          ]),
          _roomId,
          delete: calls.delete);
      expect(calls.log, ["delete room $_roomId"]);
    });

    test("does nothing for a room on the default", () async {
      final calls = _Calls();
      await RoomOwnPushRule.clear(
          _rules(room: [_rule("!other:example.org", [])]), _roomId,
          delete: calls.delete);
      expect(calls.log, isEmpty);
    });
  });

  group("set (an explicit level)", () {
    test("All Messages writes a rule even where the default notifies",
        () async {
      final calls = _Calls();
      await RoomOwnPushRule.set(_rules(), _roomId, PushRule.notify,
          delete: calls.delete, put: calls.put);
      expect(calls.log, ["put room $_roomId [notify]"]);
    });

    test("Mentions & Keywords writes a rule even where it is the default",
        () async {
      final calls = _Calls();
      await RoomOwnPushRule.set(
          _rules(groupNotifies: false), _roomId, PushRule.mentionsOnly,
          delete: calls.delete, put: calls.put);
      expect(calls.log, ["put room $_roomId []"]);
    });

    test("unmuting to a level removes the mute first", () async {
      final calls = _Calls();
      await RoomOwnPushRule.set(
          _rules(override: [_mute(_roomId)]), _roomId, PushRule.notify,
          delete: calls.delete, put: calls.put);
      expect(calls.log,
          ["delete override $_roomId", "put room $_roomId [notify]"]);
    });

    test("Mute replaces the room rule with a mute", () async {
      final calls = _Calls();
      await RoomOwnPushRule.set(
          _rules(room: [
            _rule(_roomId, ["notify"])
          ]),
          _roomId,
          PushRule.dontNotify,
          delete: calls.delete,
          put: calls.put);
      expect(calls.log, [
        "delete room $_roomId",
        "put override $_roomId [] event_match:room_id=$_roomId",
      ]);
    });
  });
}
