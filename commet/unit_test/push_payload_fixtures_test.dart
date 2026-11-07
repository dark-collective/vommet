// Vommet issue 1047, step 3: the pushes Synapse and Tuwunel really sent
// (unit_test/fixtures/push/, from the push pipeline integration test),
// through the decision code of the background push handler, without a
// network or database. See unit_test/fixtures/push/README.md.
//
// The seam: BackgroundNotificationsManager2.handleMessage fetches the event
// from the database, builds a MessageNotificationContent and hands it to
// applyPushRules, which runs PushRuleCheck and sets ruleSound / isMention
// from the verdict. Before that, the push receiver calls
// MessageNotificationContent.notePush with the push (tweaks). The fetch
// and the room facts need a client; here the event comes from the full
// format's payload and the facts are the ones the integration test set up.
// notePush, PushRuleCheck, playsSound and playsMentionSound are the real
// ones; only the two lines of applyPushRules that copy the verdict onto the
// notification are repeated (_applyVerdict).
import 'dart:convert';
import 'dart:io';

import 'package:commet/client/components/push_notification/notification_content.dart';
import 'package:commet/client/matrix/push_rule_levels.dart';
import 'package:commet/utils/push_rule_check.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;

const _dir = "unit_test/fixtures/push";
const _me = "@alice:example.org";
const _servers = ["synapse", "tuwunel"];
const _formats = ["event_id_only", "full"];

void _log(String s) {
  // ignore: avoid_print
  print("PUSHFIX $s");
}

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

/// The spec's default rules (Synapse's), plus the keyword rule the
/// integration test adds the way Settings > Notifications does. Tuwunel's
/// defaults also have the MSC3664 reply rule before the mention rule (as in
/// push_rule_check_test.dart's tuwunelRules()).
matrix.PushRuleSet _rules(String server, String keyword) =>
    matrix.PushRuleSet.fromJson({
      "override": [
        {..._rule(".m.rule.master", []), "enabled": false},
        if (server == "tuwunel")
          _rule(".im.nheko.msc3664.reply", [
            "notify",
            _sound,
            _highlight
          ], [
            {
              "kind": "im.nheko.msc3664.related_event_match",
              "key": "sender",
              "pattern": _me,
              "rel_type": "m.in_reply_to"
            }
          ]),
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
          "rule_id": keyword,
          "default": false,
          "enabled": true,
          "pattern": keyword,
          "actions": PushRuleRows.keywords.store(PushRuleLevel.noisy).actions,
        },
        {
          "rule_id": ".m.rule.contains_user_name",
          "default": true,
          "enabled": true,
          "pattern": "alice",
          "actions": ["notify", _sound, _highlight],
        },
      ],
      "room": <Object?>[],
      "sender": <Object?>[],
      "underride": [
        _rule(".m.rule.call", [
          "notify",
          _ring
        ], [
          _match("type", "m.call.invite"),
        ]),
        _rule(".m.rule.encrypted_room_one_to_one", [
          "notify",
          _sound
        ], [
          {"kind": "room_member_count", "is": "2"},
          _match("type", "m.room.encrypted"),
        ]),
        _rule(".m.rule.room_one_to_one", [
          "notify",
          _sound
        ], [
          {"kind": "room_member_count", "is": "2"},
          _match("type", "m.room.message"),
        ]),
        _rule(".m.rule.message", [
          "notify"
        ], [
          _match("type", "m.room.message"),
        ]),
        _rule(".m.rule.encrypted", [
          "notify"
        ], [
          _match("type", "m.room.encrypted"),
        ]),
      ],
    });

Map<String, dynamic> _load(String server, String name, String format) {
  final file = File("$_dir/$server/$name-$format.json");
  final body = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  return Map<String, dynamic>.from(body["notification"] as Map);
}

/// The room facts the integration test set up: alice and bob in every room,
/// carol too in group3; bob created the rooms.
PushRoomFacts _facts(String name, String roomId) => PushRoomFacts(
      roomId: roomId,
      ownUserId: _me,
      joinedMemberCount: name == "group3" ? 3 : 2,
      ownDisplayName: "alice",
      senderPowerLevel: 100,
      notificationPowerLevels: const {},
    );

/// As applyPushRules in background_service_task_notification2.dart.
void _applyVerdict(MessageNotificationContent content, PushVerdict? verdict) {
  if (verdict == null) return;
  content.ruleSound = verdict.sound;
  if (verdict.highlight) content.isMention = true;
}

class _Outcome {
  const _Outcome(this.verdict, this.sound, this.highlight);

  final PushVerdict? verdict;
  final bool sound;
  final bool highlight;
}

/// One push through the handler's decisions. [event] is the event as the
/// handler would fetch it (type, sender, content).
_Outcome _run(String server, String name, String format,
    Map<String, dynamic> data, Map<String, dynamic> event) {
  // notePush remembers tweaks by event id in static sets; both formats (and
  // both servers' fixtures) share event ids, so each run gets its own.
  final eventId = "${data["event_id"]}~$server~$format";
  final push = {...data, "event_id": eventId};
  final roomId = data["room_id"] as String;
  MessageNotificationContent.notePush(push);

  final content = MessageNotificationContent(
      senderName: event["sender_display_name"] as String? ?? "bob",
      senderId: event["sender"] as String,
      roomName: roomId,
      content: (event["content"] as Map)["body"] as String? ?? "",
      eventId: eventId,
      roomId: roomId,
      clientId: "client-alice",
      isDirectMessage: false);

  final body = (event["content"] as Map)["body"];
  final keyword =
      RegExp(r"pushkw\w+").firstMatch(body is String ? body : "")?.group(0) ??
          "pushkwunused";
  final verdict = PushRuleCheck.evaluate(
      _rules(server, keyword),
      {
        "type": event["type"],
        "content": event["content"],
        "sender": event["sender"],
        "room_id": roomId,
      },
      _facts(name, roomId));
  _applyVerdict(content, verdict);
  return _Outcome(verdict, content.playsSound, content.playsMentionSound);
}

void main() {
  final expected =
      (jsonDecode(File("$_dir/expected.json").readAsStringSync()) as List)
          .cast<Map<String, dynamic>>();

  test("every fixture has an expected outcome and vice versa", () {
    final files = <String>{
      for (final server in _servers)
        for (final f in Directory("$_dir/$server").listSync())
          if (f.path.endsWith(".json"))
            "$server/${f.uri.pathSegments.last.replaceAll(".json", "")}"
    };
    final rows = {
      for (final r in expected) "${r["server"]}/${r["case"]}-${r["format"]}"
    };
    expect(files, rows);
  });

  for (final row in expected) {
    final server = row["server"] as String;
    final name = row["case"] as String;
    final format = row["format"] as String;
    test("$server $name $format", () {
      final data = _load(server, name, format);
      // event_id_only carries no event: the handler fetches it; here it is
      // the full format's (same event).
      final event = format == "full" ? data : _load(server, name, "full");
      expect(event["event_id"], data["event_id"]);
      final o = _run(server, name, format, data, event);
      _log("$server $name $format: ${o.verdict ?? PushRuleCheck.lastReason} "
          "sound=${o.sound} highlight=${o.highlight}");

      // A fetched message event is always shown by the handler; the rules
      // must agree with the server that it notifies.
      expect(row["shown"], isTrue);
      expect(o.verdict?.notify, isNot(false), reason: "rules say no notify");
      expect(o.sound, row["sound"], reason: "sound");

      if (event["type"] == matrix.EventTypes.Encrypted) {
        // The check can't read encrypted content, so the encrypted-room
        // rules don't decide: the tweaks (or, without tweaks, the default
        // sound) do.
        expect(o.verdict, isNull);
        if (row["highlight"] == true && !o.highlight) {
          _log("SKIP $server $name $format highlight: comes from the "
              "decrypted content, which needs the room keys");
          return;
        }
      } else {
        expect(o.verdict, isNotNull, reason: PushRuleCheck.lastReason);
      }
      expect(o.highlight, row["highlight"], reason: "highlight");
    });
  }

  // Vommet issue 719: Synapse's event_id_only pushes carry no tweaks; they
  // were taken as silent.
  test("719: Synapse event_id_only pushes sound when their full twin does", () {
    var checked = 0;
    for (final row in expected) {
      if (row["server"] != "synapse" || row["format"] != "event_id_only") {
        continue;
      }
      final name = row["case"] as String;
      final full = _load("synapse", name, "full");
      if (!_run("synapse", name, "full", full, full).sound) continue;
      final data = _load("synapse", name, "event_id_only");
      final devices = data["devices"] as List;
      expect(devices.every((d) => (d as Map)["tweaks"] == null), isTrue,
          reason: "$name: Synapse event_id_only has no tweaks");
      expect(_run("synapse", name, "event_id_only", data, full).sound, isTrue,
          reason: "$name event_id_only silent, full plays a sound");
      checked++;
    }
    expect(checked, greaterThan(0));
  });

  test("formats agree per case", () {
    for (final server in _servers) {
      final names = {
        for (final r in expected)
          if (r["server"] == server) r["case"] as String
      };
      for (final name in names) {
        final full = _load(server, name, "full");
        final a = _run(
            server, name, _formats[0], _load(server, name, _formats[0]), full);
        final b = _run(server, name, _formats[1], full, full);
        if (full["type"] == matrix.EventTypes.Encrypted) {
          expect(a.sound, b.sound, reason: "$server $name sound");
          continue;
        }
        expect([a.sound, a.highlight], [b.sound, b.highlight],
            reason: "$server $name");
      }
    }
  });
}
