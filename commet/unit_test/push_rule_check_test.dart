// Vommet issue 719 follow-up: the push rules checked on the device for the
// background service, against the spec's default rules and the SDK.
import 'package:commet/client/matrix/matrix_push_rules.dart';
import 'package:commet/utils/push_rule_check.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;

const _me = "@khan:example.org";
const _other = "@grin:example.org";
const _roomId = "!room:example.org";

Map<String, Object?> _rule(String id, List<Object?> actions,
        [List<Map<String, Object?>> conditions = const []]) =>
    {
      "rule_id": id,
      "default": true,
      "enabled": true,
      "conditions": conditions,
      "actions": actions,
    };

Map<String, Object?> _match(String key, String pattern) =>
    {"kind": "event_match", "key": key, "pattern": pattern};

const _sound = {"set_tweak": "sound", "value": "default"};
const _ring = {"set_tweak": "sound", "value": "ring"};
const _highlight = {"set_tweak": "highlight"};
const _noHighlight = {"set_tweak": "highlight", "value": false};

// The spec's default rules, as Synapse serves them.
Map<String, Object?> _defaultRules() => {
      "override": [
        {..._rule(".m.rule.master", []), "enabled": false},
        _rule(".m.rule.suppress_notices", [], [
          _match("content.msgtype", "m.notice"),
        ]),
        _rule(".m.rule.invite_for_me", [
          "notify",
          _sound,
          _noHighlight,
        ], [
          _match("type", "m.room.member"),
          _match("content.membership", "invite"),
          _match("state_key", _me),
        ]),
        _rule(".m.rule.member_event", [], [
          _match("type", "m.room.member"),
        ]),
        _rule(".m.rule.is_user_mention", [
          "notify",
          _highlight,
          _sound,
        ], [
          {
            "kind": "event_property_contains",
            "key": "content.m\\.mentions.user_ids",
            "value": _me,
          },
        ]),
        _rule(".m.rule.contains_display_name", [
          "notify",
          _sound,
          _highlight,
        ], [
          {"kind": "contains_display_name"},
        ]),
        _rule(".m.rule.is_room_mention", [
          "notify",
          _highlight,
        ], [
          {
            "kind": "event_property_is",
            "key": "content.m\\.mentions.room",
            "value": true,
          },
          {"kind": "sender_notification_permission", "key": "room"},
        ]),
        _rule(".m.rule.roomnotif", [
          "notify",
          _highlight,
        ], [
          {"kind": "sender_notification_permission", "key": "room"},
          _match("content.body", "@room"),
        ]),
        _rule(".m.rule.tombstone", [
          "notify",
          _highlight,
        ], [
          _match("type", "m.room.tombstone"),
          _match("state_key", ""),
        ]),
        _rule(".m.rule.reaction", [], [
          _match("type", "m.reaction"),
        ]),
        _rule(".m.rule.server_acl", [], [
          _match("type", "m.room.server_acl"),
          _match("state_key", ""),
        ]),
        _rule(".m.rule.suppress_edits", [], [
          {
            "kind": "event_property_is",
            "key": "content.m\\.relates_to.rel_type",
            "value": "m.replace",
          },
        ]),
      ],
      "content": [
        {
          "rule_id": ".m.rule.contains_user_name",
          "default": true,
          "enabled": true,
          "pattern": "khan",
          "actions": ["notify", _sound, _highlight],
        },
      ],
      "room": <Object?>[],
      "sender": <Object?>[],
      "underride": [
        _rule(".m.rule.call", ["notify", _ring], [
          _match("type", "m.call.invite"),
        ]),
        _rule(".m.rule.encrypted_room_one_to_one", ["notify", _sound], [
          {"kind": "room_member_count", "is": "2"},
          _match("type", "m.room.encrypted"),
        ]),
        _rule(".m.rule.room_one_to_one", ["notify", _sound], [
          {"kind": "room_member_count", "is": "2"},
          _match("type", "m.room.message"),
        ]),
        _rule(".m.rule.message", ["notify"], [
          _match("type", "m.room.message"),
        ]),
        _rule(".m.rule.encrypted", ["notify"], [
          _match("type", "m.room.encrypted"),
        ]),
      ],
    };

matrix.PushRuleSet _rules([void Function(Map<String, Object?>)? edit]) {
  final json = _defaultRules();
  edit?.call(json);
  return matrix.PushRuleSet.fromJson(json);
}

Map<String, Object?> _message(Map<String, Object?> content,
        {String type = "m.room.message", String sender = _other}) =>
    {"type": type, "sender": sender, "room_id": _roomId, "content": content};

PushRoomFacts _facts({
  int? members = 5,
  String? name = "Khan",
  int? senderLevel = 0,
  Map<String, int>? notifications = const {},
}) =>
    PushRoomFacts(
      roomId: _roomId,
      ownUserId: _me,
      joinedMemberCount: members,
      ownDisplayName: name,
      senderPowerLevel: senderLevel,
      notificationPowerLevels: notifications,
    );

PushVerdict? _check(Map<String, Object?> event,
        {matrix.PushRuleSet? rules, PushRoomFacts? facts}) =>
    PushRuleCheck.evaluate(rules ?? _rules(), event, facts ?? _facts());

class _FakeSdkClient extends Fake implements matrix.Client {
  @override
  String? get userID => _me;
}

/// The SDK evaluator's answer for the same inputs, with the same MSC3952
/// handling as MatrixPushRules.
matrix.EvaluatedPushRuleAction _sdk(matrix.PushRuleSet rules,
    Map<String, Object?> event, PushRoomFacts facts) {
  final room = matrix.Room(id: _roomId, client: _FakeSdkClient());
  room.summary.mJoinedMemberCount = facts.joinedMemberCount;
  room.states[matrix.EventTypes.RoomMember] = {
    _me: matrix.StrippedStateEvent(
      type: matrix.EventTypes.RoomMember,
      senderId: _me,
      stateKey: _me,
      content: {"membership": "join", "displayname": facts.ownDisplayName},
    ),
  };
  room.states[matrix.EventTypes.RoomPowerLevels] = {
    "": matrix.StrippedStateEvent(
      type: matrix.EventTypes.RoomPowerLevels,
      senderId: _me,
      stateKey: "",
      content: {
        "users": {event["sender"]: facts.senderPowerLevel},
        "notifications": facts.notificationPowerLevels,
      },
    ),
  };
  final content = event["content"] as Map<String, Object?>;
  final used = MatrixPushRules.hasMentions(content)
      ? MatrixPushRules.withoutLegacyMentionRules(rules)
      : rules;
  return matrix.PushruleEvaluator.fromRuleset(used).match(
      matrix.Event.fromJson({
    ...event,
    "event_id": "\$event",
    "origin_server_ts": 1700000000000,
  }, room));
}

void main() {
  test("a direct message plays a sound", () {
    final v = _check(_message({"msgtype": "m.text", "body": "hi"}),
        facts: _facts(members: 2))!;
    expect([v.notify, v.sound, v.highlight], [true, true, false]);
  });

  test("a group message notifies without sound", () {
    final v = _check(_message({"msgtype": "m.text", "body": "hi"}))!;
    expect([v.notify, v.sound, v.highlight], [true, false, false]);
  });

  test("a room set to Noisy plays a sound", () {
    final rules = _rules((j) => j["room"] = [
          _rule(_roomId, ["notify", _sound])
        ]);
    final v = _check(_message({"msgtype": "m.text", "body": "hi"}),
        rules: rules)!;
    expect([v.notify, v.sound], [true, true]);
  });

  test("a muted room doesn't notify", () {
    final rules = _rules((j) => j["room"] = [
          _rule(_roomId, ["dont_notify"])
        ]);
    final v = _check(_message({"msgtype": "m.text", "body": "hi"}),
        rules: rules)!;
    expect([v.notify, v.sound], [false, false]);
  });

  test("a mention through m.mentions highlights with sound", () {
    final v = _check(_message({
      "msgtype": "m.text",
      "body": "hey",
      "m.mentions": {
        "user_ids": [_me]
      },
    }))!;
    expect([v.notify, v.sound, v.highlight], [true, true, true]);
  });

  test("the display name in the text highlights without m.mentions", () {
    final v = _check(_message({"msgtype": "m.text", "body": "hey Khan!"}))!;
    expect(v.highlight, true);
  });

  test("an empty m.mentions turns the legacy name rules off", () {
    final v = _check(_message({
      "msgtype": "m.text",
      "body": "hey Khan!",
      "m.mentions": <String, Object?>{},
    }))!;
    expect([v.highlight, v.sound], [false, false]);
  });

  test("@room highlights only when the sender may notify the room", () {
    final event = _message({
      "msgtype": "m.text",
      "body": "@room hello",
      "m.mentions": {"room": true},
    });
    expect(_check(event, facts: _facts(senderLevel: 0))!.highlight, false);
    expect(_check(event, facts: _facts(senderLevel: 50))!.highlight, true);
  });

  test("edits are suppressed", () {
    final v = _check(_message({
      "msgtype": "m.text",
      "body": "* hi",
      "m.relates_to": {"rel_type": "m.replace", "event_id": "\$x"},
    }), facts: _facts(members: 2))!;
    expect([v.notify, v.sound], [false, false]);
  });

  test("an unknown condition kind that could decide is undetermined", () {
    final rules = _rules((j) => (j["override"] as List).insert(
        0,
        _rule("custom", ["dont_notify"], [
          {"kind": "org.example.new"}
        ])));
    expect(_check(_message({"msgtype": "m.text", "body": "hi"}), rules: rules),
        isNull);
  });

  test("an unknown condition in a rule that fails anyway is ignored", () {
    final rules = _rules((j) => (j["override"] as List).insert(
        0,
        _rule("custom", ["dont_notify"], [
          {"kind": "org.example.new"},
          _match("type", "m.sticker"),
        ])));
    expect(_check(_message({"msgtype": "m.text", "body": "hi"}), rules: rules),
        isNotNull);
  });

  test("an unknown member count with room_one_to_one in play is undetermined",
      () {
    expect(
        _check(_message({"msgtype": "m.text", "body": "hi"}),
            facts: _facts(members: null)),
        isNull);
  });

  test("an unknown display name with the name rule in play is undetermined",
      () {
    expect(
        _check(_message({"msgtype": "m.text", "body": "hi"}),
            facts: _facts(name: null)),
        isNull);
  });

  test("unknown power levels with @room in play are undetermined", () {
    expect(
        _check(
            _message({
              "msgtype": "m.text",
              "body": "x",
              "m.mentions": {"room": true},
            }),
            facts: _facts(senderLevel: null)),
        isNull);
  });

  test("a still encrypted event is undetermined", () {
    expect(_check(_message({"algorithm": "x"}, type: "m.room.encrypted")),
        isNull);
  });

  test("the master rule turns notifications off", () {
    final rules = _rules((j) =>
        ((j["override"] as List).first as Map<String, Object?>)["enabled"] =
            true);
    final v = _check(_message({"msgtype": "m.text", "body": "hi"}),
        rules: rules, facts: _facts(members: 2))!;
    expect([v.notify, v.sound], [false, false]);
  });

  group("same verdict as the SDK evaluator", () {
    final noisy = _rules((j) => j["room"] = [
          _rule(_roomId, ["notify", _sound])
        ]);
    final keyword = _rules((j) => (j["content"] as List).add({
          "rule_id": "cat",
          "default": false,
          "enabled": true,
          "pattern": "ca?s*",
          "actions": ["notify", _sound],
        }));
    final cases = <String,
        (matrix.PushRuleSet, Map<String, Object?>, PushRoomFacts)>{
      "dm": (
        _rules(),
        _message({"msgtype": "m.text", "body": "hi"}),
        _facts(members: 2)
      ),
      "group": (
        _rules(),
        _message({"msgtype": "m.text", "body": "hi"}),
        _facts()
      ),
      "noisy": (
        noisy,
        _message({"msgtype": "m.text", "body": "hi"}),
        _facts()
      ),
      "name": (
        _rules(),
        _message({"msgtype": "m.text", "body": "KHAN?"}),
        _facts()
      ),
      "name with m.mentions": (
        _rules(),
        _message({"msgtype": "m.text", "body": "Khan", "m.mentions": {}}),
        _facts()
      ),
      "user mention": (
        _rules(),
        _message({
          "msgtype": "m.text",
          "body": "x",
          "m.mentions": {
            "user_ids": [_me]
          }
        }),
        _facts()
      ),
      "room mention PL 0": (
        _rules(),
        _message({"msgtype": "m.text", "body": "@room x"}),
        _facts(senderLevel: 0)
      ),
      "room mention PL 50": (
        _rules(),
        _message({"msgtype": "m.text", "body": "@room x"}),
        _facts(senderLevel: 50)
      ),
      "notice": (
        _rules(),
        _message({"msgtype": "m.notice", "body": "bot"}),
        _facts(members: 2)
      ),
      "keyword glob": (
        keyword,
        _message({"msgtype": "m.text", "body": "my cats!"}),
        _facts()
      ),
      "keyword glob, no word": (
        keyword,
        _message({"msgtype": "m.text", "body": "scats"}),
        _facts()
      ),
    };
    for (final c in cases.entries) {
      test(c.key, () {
        final (rules, event, facts) = c.value;
        final ours = PushRuleCheck.evaluate(rules, event, facts)!;
        final sdk = _sdk(rules, event, facts);
        expect([ours.notify, ours.sound, ours.highlight],
            [sdk.notify, sdk.sound != null, sdk.highlight]);
      });
    }
  });
}
