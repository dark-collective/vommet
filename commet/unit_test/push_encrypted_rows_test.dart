// Vommet issue 918: the device checks a message from an encrypted room once
// it is decrypted, so it matched the plain rows ("Group chats", "One-to-one
// chats"), not the "Encrypted …" rows the grid and the room's badge show for
// it. With only the encrypted rows at Noisy it notified silently. A plain
// row that notifies quietly now takes the encrypted row's sound in an
// encrypted room, in the app (RoomPushRules) and in the background service
// (PushRuleCheck) alike; nothing gets quieter.
import 'package:commet/client/matrix/matrix_push_rules.dart';
import 'package:commet/utils/push_rule_check.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;

const _me = "@khan:example.org";
const _other = "@grin:example.org";
const _roomId = "!room:example.org";

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
  String? pattern,
}) {
  return {
    "rule_id": id,
    "default": isDefault,
    "enabled": true,
    "conditions": conditions,
    "actions": actions,
    if (pattern != null) "pattern": pattern,
  };
}

Map<String, Object?> _type(String type) {
  return {"kind": "event_match", "key": "type", "pattern": type};
}

const _twoPeople = {"kind": "room_member_count", "is": "2"};

/// The grid's message rows: one-to-one, encrypted one-to-one, group chats
/// and encrypted group chats.
matrix.PushRuleSet _rules({
  List<Object?> oneToOne = _noisy,
  List<Object?> encryptedOneToOne = _noisy,
  List<Object?> group = _noisy,
  List<Object?> encryptedGroup = _noisy,
  List<Object?> room = const [],
  List<Object?> content = const [],
}) {
  final encrypted = _type("m.room.encrypted");
  final message = _type("m.room.message");
  return matrix.PushRuleSet.fromJson({
    "override": const [],
    "content": content,
    "room": room,
    "sender": const [],
    "underride": [
      _rule(".m.rule.encrypted_room_one_to_one", encryptedOneToOne,
          conditions: [_twoPeople, encrypted]),
      _rule(".m.rule.room_one_to_one", oneToOne,
          conditions: [_twoPeople, message]),
      _rule(".m.rule.message", group, conditions: [message]),
      _rule(".m.rule.encrypted", encryptedGroup, conditions: [encrypted]),
    ],
  });
}

/// A decrypted text message.
Map<String, Object?> _message({String body = "hi"}) {
  return {
    "type": "m.room.message",
    "sender": _other,
    "room_id": _roomId,
    "content": {"msgtype": "m.text", "body": body},
  };
}

/// What the app finds: (notify, sound, highlight).
(bool, bool, bool) _app(
  matrix.PushRuleSet rules,
  Map<String, Object?> json, {
  required bool encrypted,
  int members = 5,
}) {
  final summary = {"m.joined_member_count": members};
  final room = matrix.Room(
    id: _roomId,
    client: _FakeSdkClient(),
    summary: matrix.RoomSummary.fromJson(summary),
  );
  if (encrypted) {
    room.states[matrix.EventTypes.Encryption] = {
      "": matrix.StrippedStateEvent(
        type: matrix.EventTypes.Encryption,
        senderId: _other,
        stateKey: "",
        content: {"algorithm": "m.megolm.v1.aes-sha2"},
      ),
    };
  }
  final event = matrix.Event.fromJson(
    {...json, "event_id": r"$event", "origin_server_ts": 1700000000000},
    room,
  );
  final action = RoomPushRules(rules).match(event);
  return (action.notify, action.sound != null, action.highlight);
}

/// What the background service finds: (notify, sound, highlight).
(bool, bool, bool) _background(
  matrix.PushRuleSet rules,
  Map<String, Object?> json, {
  required bool encrypted,
  int members = 5,
}) {
  final facts = PushRoomFacts(
    roomId: _roomId,
    ownUserId: _me,
    joinedMemberCount: members,
    encryptedRoom: encrypted,
  );
  final verdict = PushRuleCheck.evaluate(rules, json, facts)!;
  return (verdict.notify, verdict.sound, verdict.highlight);
}

void main() {
  final paths = {"app": _app, "background": _background};

  for (final path in paths.entries) {
    final check = path.value;

    group(path.key, () {
      test("Encrypted group chats at Noisy ring in an encrypted room", () {
        final rules = _rules(group: _on);
        final result = check(rules, _message(), encrypted: true);
        expect(result, (true, true, false));
      });

      test("Group chats at On stay quiet in an unencrypted room", () {
        final rules = _rules(group: _on);
        final result = check(rules, _message(), encrypted: false);
        expect(result, (true, false, false));
      });

      test("Encrypted one-to-one chats at Noisy ring in an encrypted DM", () {
        final rules = _rules(oneToOne: _on);
        final result = check(rules, _message(), encrypted: true, members: 2);
        expect(result, (true, true, false));
      });

      test("both group rows at On stay quiet in an encrypted room", () {
        final rules = _rules(group: _on, encryptedGroup: _on);
        final result = check(rules, _message(), encrypted: true);
        expect(result, (true, false, false));
      });

      test("nothing gets quieter: Group chats Noisy, encrypted On", () {
        final rules = _rules(encryptedGroup: _on);
        final result = check(rules, _message(), encrypted: true);
        expect(result, (true, true, false));
      });

      test("Group chats Off still don't notify", () {
        final rules = _rules(group: _off);
        final result = check(rules, _message(), encrypted: true);
        expect(result, (false, false, false));
      });

      test("a keyword at On stays quiet in an encrypted room", () {
        final keyword = _rule("tea", _on, isDefault: false, pattern: "tea");
        final rules = _rules(group: _on, content: [keyword]);
        final json = _message(body: "tea time");
        final result = check(rules, json, encrypted: true);
        expect(result, (true, false, false));
      });

      test("All Messages on an encrypted room follows the encrypted row", () {
        final all = _rule(_roomId, _on, isDefault: false);
        final rules = _rules(group: _on, room: [all]);
        final result = check(rules, _message(), encrypted: true);
        expect(result, (true, true, false));
      });

      test("the highlight is kept", () {
        final keyword = _rule("tea", ["notify", _highlight],
            isDefault: false, pattern: "tea");
        final rules = _rules(content: [keyword]);
        final json = _message(body: "tea time");
        final result = check(rules, json, encrypted: true);
        expect(result, (true, false, true));
      });
    });
  }

  test("only plain rows that notify quietly change", () {
    expect(MatrixPushRules.withEncryptedRowsSound(_rules()), isNull);
    expect(
        MatrixPushRules.withEncryptedRowsSound(
            _rules(group: _on, encryptedGroup: _on)),
        isNull);
    final changed = MatrixPushRules.withEncryptedRowsSound(_rules(group: _on))!;
    final message =
        changed.underride!.firstWhere((r) => r.ruleId == ".m.rule.message");
    expect(message.actions, ["notify", _sound]);
  });
}
