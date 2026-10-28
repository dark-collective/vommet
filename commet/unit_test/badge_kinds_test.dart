// Vommet issue 719: three kinds of badge. Unread rooms get a dot, silent
// notifications a grey number, and noisy ones (mentions, keywords, and
// messages whose push rule plays a sound) a red number. "Noisy" comes from
// the account's real push rules, as Element and the spec define them.
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'package:commet/client/matrix/matrix_push_rules.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/client/room.dart';
import 'package:commet/ui/atoms/notification_badge.dart';
import 'package:commet/ui/organisms/new_home/new_home_people_store.dart';
import 'package:commet/utils/badge_rules.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;

const _me = "@khan:example.org";
const _roomId = "!room:example.org";

class _FakeSdkClient extends Fake implements matrix.Client {
  @override
  String? get userID => _me;
}

class _Dm extends Fake implements Room {
  _Dm(this.notificationCount, {this.badgeNoisy = false});

  @override
  final int notificationCount;

  @override
  final bool badgeNoisy;
}

Map<String, Object?> _rule(String id, List<Object?> conditions,
        {bool sound = false}) =>
    {
      "rule_id": id,
      "default": true,
      "enabled": true,
      "conditions": conditions,
      "actions": [
        "notify",
        if (sound) {"set_tweak": "sound", "value": "default"},
      ],
    };

Map<String, Object?> _type(String type) =>
    {"kind": "event_match", "key": "type", "pattern": type};

const _oneToOne = {"kind": "room_member_count", "is": "2"};

/// The spec's default underride rules for messages (Matrix 1.16): one-to-one
/// chats play a sound, group chats don't.
final _defaultUnderride = [
  _rule(".m.rule.room_one_to_one", [_oneToOne, _type("m.room.message")],
      sound: true),
  _rule(".m.rule.encrypted_room_one_to_one",
      [_oneToOne, _type("m.room.encrypted")],
      sound: true),
  _rule(".m.rule.message", [_type("m.room.message")]),
  _rule(".m.rule.encrypted", [_type("m.room.encrypted")]),
];

RoomPushRules _evaluator(
        {List<Object?> room = const [], List<Object?>? underride}) =>
    RoomPushRules(matrix.PushRuleSet.fromJson({
      "override": const [],
      "content": const [],
      "room": room,
      "sender": const [],
      "underride": underride ?? _defaultUnderride,
    }));

/// [members] loaded on the device; [joined] is the server's count in the
/// room summary, when it sent one.
matrix.Room _room({required int members, bool encrypted = false, int? joined}) {
  final room = matrix.Room(
      id: _roomId,
      client: _FakeSdkClient(),
      summary: matrix.RoomSummary.fromJson(
          {if (joined != null) "m.joined_member_count": joined}));
  room.states[matrix.EventTypes.RoomMember] = {
    for (var i = 0; i < members; i++)
      (i == 0 ? _me : "@member$i:example.org"): matrix.StrippedStateEvent(
        type: matrix.EventTypes.RoomMember,
        senderId: _me,
        stateKey: i == 0 ? _me : "@member$i:example.org",
        content: {"membership": "join"},
      ),
  };
  if (encrypted) {
    room.states[matrix.EventTypes.Encryption] = {
      "": matrix.StrippedStateEvent(
        type: matrix.EventTypes.Encryption,
        senderId: _me,
        stateKey: "",
        content: {"algorithm": "m.megolm.v1.aes-sha2"},
      ),
    };
  }
  return room;
}

void main() {
  group("badge rules", () {
    test("a room on All messages counts every notifying message", () {
      expect(BadgeRules.count(notifications: 7, highlights: 2), 7);
    });

    test("a room on Mentions & Keywords counts its mentions", () {
      expect(BadgeRules.count(notifications: 0, highlights: 3), 3);
    });

    test("nothing counted leaves the unread dot", () {
      expect(BadgeRules.count(notifications: 0, highlights: 0), 0);
      expect(
          BadgeRules.noisy(
              notifications: 0, highlights: 0, messagesAreNoisy: true),
          isFalse);
    });

    test("silent messages are grey", () {
      expect(
          BadgeRules.noisy(
              notifications: 5, highlights: 0, messagesAreNoisy: false),
          isFalse);
    });

    test("noisy messages are red", () {
      expect(
          BadgeRules.noisy(
              notifications: 5, highlights: 0, messagesAreNoisy: true),
          isTrue);
    });

    test("a mention makes a silent room red", () {
      expect(
          BadgeRules.noisy(
              notifications: 5, highlights: 1, messagesAreNoisy: false),
          isTrue);
    });
  });

  group("noisy from the push rules", () {
    test("a direct message plays a sound under the default rules", () {
      expect(MatrixRoom.messagesNoisyUnder(_evaluator(), _room(members: 2)),
          isTrue);
    });

    test("an encrypted direct message too", () {
      expect(
          MatrixRoom.messagesNoisyUnder(
              _evaluator(), _room(members: 2, encrypted: true)),
          isTrue);
    });

    test("a group chat is silent under the default rules", () {
      expect(MatrixRoom.messagesNoisyUnder(_evaluator(), _room(members: 3)),
          isFalse);
      expect(
          MatrixRoom.messagesNoisyUnder(
              _evaluator(), _room(members: 5, encrypted: true)),
          isFalse);
    });

    // Vommet issue 745: the SDK counted only the members loaded on the
    // device, so a direct message whose members weren't loaded fell to the
    // group chat rules (here Off) and showed a dot instead of its count.
    test("a direct message counts its members as the server does", () {
      final groupChatsOff = _evaluator(underride: [
        ..._defaultUnderride.take(2),
        {..._defaultUnderride[2], "actions": const []},
        {..._defaultUnderride[3], "actions": const []},
      ]);
      final dm = _room(members: 1, encrypted: true, joined: 2);
      expect(groupChatsOff.match(MatrixRoom.ordinaryMessageProbe(dm)).notify,
          isTrue);
      expect(MatrixRoom.messagesNoisyUnder(groupChatsOff, dm), isTrue);
    });

    test("a big room with two members loaded isn't a one-to-one chat", () {
      expect(
          MatrixRoom.messagesNoisyUnder(
              _evaluator(), _room(members: 2, encrypted: true, joined: 30)),
          isFalse);
    });

    test("member count conditions", () {
      expect(MatrixPushRules.memberCountMatches("2", 2), isTrue);
      expect(MatrixPushRules.memberCountMatches("==2", 3), isFalse);
      expect(MatrixPushRules.memberCountMatches(">=3", 3), isTrue);
      expect(MatrixPushRules.memberCountMatches("<3", 3), isFalse);
      expect(MatrixPushRules.memberCountMatches(">2", 3), isTrue);
      expect(MatrixPushRules.memberCountMatches("<=1", 1), isTrue);
      expect(MatrixPushRules.memberCountMatches("lots", 3), isNull);
    });

    test("a room rule with a sound makes a group chat noisy", () {
      final evaluator = _evaluator(room: [
        {
          "rule_id": _roomId,
          "default": false,
          "enabled": true,
          "actions": [
            "notify",
            {"set_tweak": "sound", "value": "default"}
          ],
        }
      ]);
      expect(
          MatrixRoom.messagesNoisyUnder(evaluator, _room(members: 3)), isTrue);
    });

    test("a room rule that doesn't notify is never noisy", () {
      final evaluator = _evaluator(room: [
        {
          "rule_id": _roomId,
          "default": false,
          "enabled": true,
          "actions": const [],
        }
      ]);
      expect(
          MatrixRoom.messagesNoisyUnder(evaluator, _room(members: 2)), isFalse);
    });
  });

  group("mentions found on the device in encrypted rooms", () {
    test("count until the room is read", () {
      final highlights = {r"$a": 100, r"$b": 200, r"$c": 300};
      expect(MatrixRoom.unreadLocalHighlights(highlights, 0), 3);
      expect(MatrixRoom.unreadLocalHighlights(highlights, 200), 1);
      expect(highlights.keys, [r"$c"]);
      expect(MatrixRoom.unreadLocalHighlights(highlights, 300), 0);
    });
  });

  group("the People badge", () {
    test("is red for an invite", () {
      expect(NewHomeInvites.isBadgeNoisy(1, const []), isTrue);
    });

    test("is red for a noisy direct message", () {
      expect(
          NewHomeInvites.isBadgeNoisy(
              0, [_Dm(0, badgeNoisy: true), _Dm(3, badgeNoisy: true)]),
          isTrue);
    });

    test("is grey when it only counts silent messages", () {
      expect(NewHomeInvites.isBadgeNoisy(0, [_Dm(3), _Dm(0, badgeNoisy: true)]),
          isFalse);
    });
  });

  testWidgets("the badge is red when noisy and grey when silent",
      (tester) async {
    Color color() {
      final box = tester.widget<Container>(find.descendant(
          of: find.byType(NotificationBadge),
          matching: find.byType(Container)));
      return (box.decoration as BoxDecoration).color!;
    }

    await tester.pumpWidget(const MaterialApp(home: NotificationBadge(4)));
    expect(color(), Colors.red.shade600);

    await tester.pumpWidget(
        const MaterialApp(home: NotificationBadge(4, noisy: false)));
    expect(color(), silentBadgeColor);
  });
}
