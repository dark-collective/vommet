// Vommet issue 918: the reporter's setup as closely as unit tests get: Synapse's full default rule set (synapse
// rust/src/push/base_rules.rs, experimental rules left out), every grid row
// Noisy as Vommet writes it (PushRuleRow.store), then each kind of message,
// through the entry points the Android notifier really calls:
// MatrixPushRules.match (app running, AndroidNotifier._messageContent) and
// PushRuleCheck.evaluate (background service, applyPushRules).
import 'package:commet/client/matrix/components/threads/thread_reply_rules.dart';
import 'package:commet/client/matrix/matrix_push_rules.dart';
import 'package:commet/client/matrix/push_rule_levels.dart';
import 'package:commet/utils/push_rule_check.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;

const _me = "@communist:4d2.org";
const _other = "@friend:4d2.org";
const _roomId = "!room:4d2.org";
const _root = r"$root";

Map<String, Object?> _m(String key, String pattern) =>
    {"kind": "event_match", "key": key, "pattern": pattern};

Map<String, Object?> _r(String id, List<Object?> actions,
        {List<Object?> conditions = const [],
        bool isDefault = true,
        bool enabled = true,
        String? pattern}) =>
    {
      "rule_id": id,
      "default": isDefault,
      "enabled": enabled,
      "conditions": conditions,
      "actions": actions,
      if (pattern != null) "pattern": pattern,
    };

const _hl = {"set_tweak": "highlight"};
const _hlFalse = {"set_tweak": "highlight", "value": false};
const _snd = {"set_tweak": "sound", "value": "default"};
const _ring = {"set_tweak": "sound", "value": "ring"};

/// Synapse's defaults as /pushrules/ serves them (non-experimental).
Map<String, List<Map<String, Object?>>> _synapseDefaults() => {
      "override": [
        _r(".m.rule.master", [], enabled: false),
        _r(".m.rule.suppress_notices", [],
            conditions: [_m("content.msgtype", "m.notice")]),
        _r(".m.rule.invite_for_me", [
          "notify",
          _hlFalse,
          _snd
        ], conditions: [
          _m("type", "m.room.member"),
          _m("content.membership", "invite"),
          _m("state_key", _me)
        ]),
        _r(".m.rule.member_event", [],
            conditions: [_m("type", "m.room.member")]),
        _r(".m.rule.is_user_mention", [
          "notify",
          _hl,
          _snd
        ], conditions: [
          {
            "kind": "event_property_contains",
            "key": r"content.m\.mentions.user_ids",
            "value": _me
          }
        ]),
        _r(".m.rule.contains_display_name", [
          "notify",
          _hl,
          _snd
        ], conditions: [
          {"kind": "contains_display_name"}
        ]),
        _r(".m.rule.is_room_mention", [
          "notify",
          _hl
        ], conditions: [
          {
            "kind": "event_property_is",
            "key": r"content.m\.mentions.room",
            "value": true
          },
          {"kind": "sender_notification_permission", "key": "room"}
        ]),
        _r(".m.rule.roomnotif", [
          "notify",
          _hl
        ], conditions: [
          {"kind": "sender_notification_permission", "key": "room"},
          _m("content.body", "@room"),
        ]),
        _r(".m.rule.tombstone", ["notify", _hl],
            conditions: [_m("type", "m.room.tombstone"), _m("state_key", "")]),
        _r(".m.rule.reaction", [], conditions: [_m("type", "m.reaction")]),
        _r(".m.rule.room.server_acl", [],
            conditions: [_m("type", "m.room.server_acl"), _m("state_key", "")]),
        _r(".m.rule.suppress_edits", [], conditions: [
          {
            "kind": "event_property_is",
            "key": r"content.m\.relates_to.rel_type",
            "value": "m.replace"
          }
        ]),
      ],
      "content": [
        _r(".m.rule.contains_user_name", ["notify", _hl, _snd],
            pattern: "communist"),
      ],
      "room": [],
      "sender": [],
      "underride": [
        _r(".m.rule.call", ["notify", _ring, _hlFalse],
            conditions: [_m("type", "m.call.invite")]),
        _r(".m.rule.encrypted_room_one_to_one", [
          "notify",
          _snd,
          _hlFalse
        ], conditions: [
          {"kind": "room_member_count", "is": "2"},
          _m("type", "m.room.encrypted")
        ]),
        _r(".m.rule.room_one_to_one", [
          "notify",
          _snd,
          _hlFalse
        ], conditions: [
          {"kind": "room_member_count", "is": "2"},
          _m("type", "m.room.message")
        ]),
        _r(".m.rule.message", ["notify", _hlFalse],
            conditions: [_m("type", "m.room.message")]),
        _r(".m.rule.encrypted", ["notify", _hlFalse],
            conditions: [_m("type", "m.room.encrypted")]),
        _r(".im.vector.jitsi", [
          "notify",
          _hlFalse
        ], conditions: [
          _m("type", "im.vector.modular.widgets"),
          _m("content.type", "jitsi"),
          _m("state_key", "*")
        ]),
      ],
    };

/// Every grid row set to Noisy, as the settings page stores it.
Map<String, List<Map<String, Object?>>> _allNoisy(
    Map<String, List<Map<String, Object?>>> json) {
  final rows = [
    ...PushRuleRows.messages,
    ...PushRuleRows.mentionsAndKeywords,
    ...PushRuleRows.other
  ];
  for (final list in json.values) {
    for (final rule in list) {
      for (final row in rows) {
        if (row.ruleIds.contains(rule["rule_id"])) {
          final s = row.store(PushRuleLevel.noisy);
          rule["enabled"] = s.enabled;
          rule["actions"] = s.actions;
        }
      }
    }
  }
  return json;
}

matrix.PushRuleSet _set({
  List<Map<String, Object?>> room = const [],
  List<Map<String, Object?>> underrideFirst = const [],
}) {
  final json = _allNoisy(_synapseDefaults());
  json["room"] = [...room];
  json["underride"] = [...underrideFirst, ...json["underride"]!];
  return matrix.PushRuleSet.fromJson(json);
}

class _FakeClient extends Fake implements matrix.Client {
  _FakeClient(this.rules);
  final matrix.PushRuleSet rules;
  late final _accountData = {
    matrix.EventTypes.PushRules: matrix.BasicEvent(
        type: matrix.EventTypes.PushRules, content: {"global": {}}),
  };
  @override
  String? get userID => _me;
  @override
  matrix.PushRuleSet? get globalPushRules => rules;
  @override
  Map<String, matrix.BasicEvent> get accountData => _accountData;
}

/// (notify, sound, highlight) in the running app (MatrixPushRules.match).
(bool, bool, bool) _app(
    matrix.PushRuleSet rules, Map<String, Object?> json, int members) {
  final room = matrix.Room(
    id: _roomId,
    client: _FakeClient(rules),
    summary: matrix.RoomSummary.fromJson({"m.joined_member_count": members}),
  );
  room.states[matrix.EventTypes.RoomMember] = {
    _me: matrix.StrippedStateEvent(
        type: matrix.EventTypes.RoomMember,
        senderId: _me,
        stateKey: _me,
        content: {"membership": "join", "displayname": "Communist"}),
  };
  room.states[matrix.EventTypes.RoomPowerLevels] = {
    "": matrix.StrippedStateEvent(
        type: matrix.EventTypes.RoomPowerLevels,
        senderId: _other,
        stateKey: "",
        content: {
          "users": {_other: 100}
        }),
  };
  final event = matrix.Event.fromJson(
      {...json, "event_id": r"$ev", "origin_server_ts": 1700000000000}, room);
  final a = MatrixPushRules.match(event);
  return (a.notify, a.sound != null, a.highlight);
}

/// (notify, sound, highlight) in the background service; null = undetermined
/// (which plays the sound).
(bool, bool, bool)? _bg(
    matrix.PushRuleSet rules, Map<String, Object?> json, int members) {
  final v = PushRuleCheck.evaluate(
      rules,
      json,
      PushRoomFacts(
          roomId: _roomId,
          ownUserId: _me,
          joinedMemberCount: members,
          ownDisplayName: "Communist",
          senderPowerLevel: 100,
          notificationPowerLevels: const {}));
  return v == null ? null : (v.notify, v.sound, v.highlight);
}

Map<String, Object?> _msg(Map<String, Object?> content,
        {String type = "m.room.message"}) =>
    {
      "type": type,
      "sender": _other,
      "room_id": _roomId,
      "content": {"msgtype": "m.text", "body": "hello", ...content},
    };

void main() {
  final cases = <String, (Map<String, Object?>, int)>{
    "DM text": (_msg({}), 2),
    "DM text with empty m.mentions": (_msg({"m.mentions": {}}), 2),
    "group text": (_msg({}), 5),
    "group text with m.mentions empty": (_msg({"m.mentions": {}}), 5),
    "group image": (_msg({"msgtype": "m.image", "body": "x.jpg"}), 5),
    "group notice (bot)": (_msg({"msgtype": "m.notice"}), 5),
    "group reply": (
      _msg({
        "m.relates_to": {
          "m.in_reply_to": {"event_id": r"$x"}
        }
      }),
      5
    ),
    "group thread reply": (
      _msg({
        "m.relates_to": {"rel_type": "m.thread", "event_id": _root}
      }),
      5
    ),
    "group @room (m.mentions)": (
      _msg({
        "body": "@room hi",
        "m.mentions": {"room": true}
      }),
      5
    ),
    "group user mention (m.mentions)": (
      _msg({
        "m.mentions": {
          "user_ids": [_me]
        }
      }),
      5
    ),
    "group display name in text, no m.mentions": (
      _msg({"body": "hey Communist"}),
      5
    ),
  };

  final roomSetups = <String, matrix.PushRuleSet>{
    "grid only": _set(),
    "Vommet room All Messages": _set(room: [
      _r(_roomId, ["notify"], isDefault: false)
    ]),
    "Element X room All messages": _set(room: [
      _r(_roomId, ["notify", _snd], isDefault: false)
    ]),
    "Only threads I'm in + thread you're in": _set(underrideFirst: [
      _r(ThreadReplyRules.threadId(_root), ["notify"],
          isDefault: false,
          conditions: [
            _m("room_id", _roomId),
            _m(r"content.m\.relates_to.event_id", _root)
          ]),
      _r(ThreadReplyRules.globalMuteId, [],
          isDefault: false,
          conditions: [
            _m("type", "m.room.message"),
            _m(r"content.m\.relates_to.rel_type", "m.thread")
          ]),
    ]),
    "Vommet room All Messages + Only threads I'm in": _set(room: [
      _r(_roomId, ["notify"], isDefault: false)
    ], underrideFirst: [
      _r(ThreadReplyRules.globalMuteId, [],
          isDefault: false,
          conditions: [
            _m("type", "m.room.message"),
            _m(r"content.m\.relates_to.rel_type", "m.thread")
          ]),
    ]),
  };

  for (final setup in roomSetups.entries) {
    group(setup.key, () {
      for (final c in cases.entries) {
        test("${c.key}: notifies with sound, app and background agree", () {
          final (json, members) = c.value;
          final app = _app(setup.value, json, members);
          final bg = _bg(setup.value, json, members);
          expect(app.$1, isTrue, reason: "app notifies");
          expect(app.$2, isTrue, reason: "app sound");
          if (bg != null) {
            expect(bg.$1, isTrue, reason: "bg notifies");
            expect(bg.$2, isTrue, reason: "bg sound");
          }
        });
      }
    });
  }
}
