// Vommet issue 666: the legacy mention rules don't apply to messages that
// carry m.mentions (MSC3952), as on the homeserver and in Element.
import 'package:commet/client/matrix/matrix_push_rules.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;

const _me = "@khan:example.org";

class _FakeSdkClient extends Fake implements matrix.Client {
  @override
  String? get userID => _me;

  // MatrixPushRules.match reads the account's rules from here.
  late final matrix.BasicEvent _pushRules = matrix.BasicEvent(
    type: matrix.EventTypes.PushRules,
    content: {"global": _rules.toJson()},
  );

  @override
  Map<String, matrix.BasicEvent> get accountData =>
      {matrix.EventTypes.PushRules: _pushRules};

  @override
  matrix.PushRuleSet? get globalPushRules => _rules;
}

const _roomId = "!room:example.org";

// A room at "Mentions & Keywords": a room rule without actions, plus the
// default override and content rules.
final _rules = matrix.PushRuleSet.fromJson({
  "override": [
    {
      "rule_id": ".m.rule.is_user_mention",
      "default": true,
      "enabled": true,
      "conditions": [
        {
          "kind": "event_property_contains",
          "key": "content.m\\.mentions.user_ids",
          "value": _me,
        }
      ],
      "actions": [
        "notify",
        {"set_tweak": "highlight"}
      ],
    },
    {
      "rule_id": ".m.rule.contains_display_name",
      "default": true,
      "enabled": true,
      "conditions": [
        {"kind": "contains_display_name"}
      ],
      "actions": [
        "notify",
        {"set_tweak": "highlight"}
      ],
    },
    {
      "rule_id": ".m.rule.roomnotif",
      "default": true,
      "enabled": true,
      "conditions": [
        {"kind": "event_match", "key": "content.body", "pattern": "@room"}
      ],
      "actions": [
        "notify",
        {"set_tweak": "highlight"}
      ],
    },
  ],
  "content": [
    {
      "rule_id": ".m.rule.contains_user_name",
      "default": true,
      "enabled": true,
      "pattern": "khan",
      "actions": ["notify"],
    },
    {
      "rule_id": "keyword",
      "default": false,
      "enabled": true,
      "pattern": "pizza",
      "actions": ["notify"],
    },
  ],
  "room": [
    {"rule_id": _roomId, "default": false, "enabled": true, "actions": []}
  ],
});

matrix.Event _event(Map<String, Object?> content) {
  final room = matrix.Room(id: _roomId, client: _FakeSdkClient());
  room.states[matrix.EventTypes.RoomMember] = {
    _me: matrix.StrippedStateEvent(
      type: matrix.EventTypes.RoomMember,
      senderId: _me,
      stateKey: _me,
      content: {"membership": "join", "displayname": "Khan"},
    ),
  };
  return matrix.Event.fromJson({
    "type": matrix.EventTypes.Message,
    "event_id": "\$event",
    "sender": "@grin:example.org",
    "origin_server_ts": 1700000000000,
    "content": content,
  }, room);
}

bool _notifies(matrix.PushRuleSet rules, matrix.Event event) =>
    matrix.PushruleEvaluator.fromRuleset(rules).match(event).notify;

void main() {
  test("legacy mention rules are removed, others kept", () {
    final rules = MatrixPushRules.withoutLegacyMentionRules(_rules);
    expect(rules.override!.map((r) => r.ruleId), [".m.rule.is_user_mention"]);
    expect(rules.content!.map((r) => r.ruleId), ["keyword"]);
    expect(rules.room!.map((r) => r.ruleId), [_roomId]);
  });

  test("hasMentions looks for the property, even when empty", () {
    expect(MatrixPushRules.hasMentions({"body": "a", "m.mentions": {}}), true);
    expect(MatrixPushRules.hasMentions({"body": "a"}), false);
  });

  test("a picture whose file name has your name no longer notifies", () {
    final picture = _event({
      "msgtype": "m.image",
      "body": "khan.jpg",
      "url": "mxc://example.org/abc",
      "m.mentions": {},
    });
    // What the SDK's evaluator said before this fix.
    expect(_notifies(_rules, picture), true);
    expect(
        _notifies(MatrixPushRules.withoutLegacyMentionRules(_rules), picture),
        false);
  });

  test("a real mention still notifies", () {
    final mention = _event({
      "msgtype": "m.text",
      "body": "Khan: look",
      "m.mentions": {
        "user_ids": [_me]
      },
    });
    expect(
        _notifies(MatrixPushRules.withoutLegacyMentionRules(_rules), mention),
        true);
  });

  test("messages without m.mentions keep the legacy rules", () {
    final old = _event({"msgtype": "m.text", "body": "hi Khan"});
    expect(MatrixPushRules.hasMentions(old.content), false);
    expect(_notifies(_rules, old), true);
  });

  test("a keyword notifies in a room at Mentions & Keywords", () {
    // The SDK checks content (keyword) rules before room rules since
    // vommet-v6.1.1-ss.29.17, as the spec orders them.
    final keyword = _event({
      "msgtype": "m.text",
      "body": "pizza tonight?",
      "m.mentions": {},
    });
    expect(_notifies(_rules, keyword), true);
    expect(MatrixPushRules.match(keyword).notify, true);
    expect(MatrixPushRules.match(keyword).highlight, false);
  });

  test("the mention flag follows the same match as the notification", () {
    // Desktop notifications take their sound and mention flag (and
    // eventMentionsMe its answer) from MatrixPushRules.match, like
    // shouldNotify: a picture named after you isn't a mention.
    final picture = _event({
      "msgtype": "m.image",
      "body": "khan.jpg",
      "url": "mxc://example.org/abc",
      "m.mentions": {},
    });
    expect(MatrixPushRules.match(picture).notify, false);
    expect(MatrixPushRules.match(picture).highlight, false);

    final mention = _event({
      "msgtype": "m.text",
      "body": "Khan: look",
      "m.mentions": {
        "user_ids": [_me]
      },
    });
    expect(MatrixPushRules.match(mention).notify, true);
    expect(MatrixPushRules.match(mention).highlight, true);
  });
}
