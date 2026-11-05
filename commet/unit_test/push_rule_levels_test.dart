// Vommet issue 719: the account's Off/On/Noisy grid reads and writes the
// same push rules as Element's settings (VectorPushRulesDefinitions).
import 'package:commet/client/matrix/push_rule_levels.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;

const _sound = {"set_tweak": "sound", "value": "default"};

Map<String, Object?> _rule(String id, List<Object?> actions,
        {bool enabled = true, bool isDefault = true, String? pattern}) =>
    {
      "rule_id": id,
      "default": isDefault,
      "enabled": enabled,
      "actions": actions,
      if (pattern != null) "pattern": pattern,
    };

/// The spec's default rules (Matrix 1.16), the ones the grid shows.
matrix.PushRuleSet _defaults({
  List<Map<String, Object?>> override = const [],
  List<Map<String, Object?>> content = const [],
  List<Map<String, Object?>> underride = const [],
}) {
  Map<String, Map<String, Object?>> byId(List<Map<String, Object?>> rules) =>
      {for (final r in rules) r["rule_id"] as String: r};
  List<Map<String, Object?>> merge(List<Map<String, Object?>> base,
          List<Map<String, Object?>> changes) =>
      [for (final r in base) byId(changes)[r["rule_id"]] ?? r] +
      [
        for (final c in changes)
          if (!base.any((r) => r["rule_id"] == c["rule_id"])) c
      ];

  return matrix.PushRuleSet.fromJson({
    "override": merge([
      _rule(".m.rule.master", const [], enabled: false),
      _rule(".m.rule.suppress_notices", const []),
      _rule(".m.rule.invite_for_me", ["notify", _sound]),
      _rule(".m.rule.is_user_mention", [
        "notify",
        _sound,
        {"set_tweak": "highlight"}
      ]),
      _rule(".m.rule.contains_display_name", [
        "notify",
        _sound,
        {"set_tweak": "highlight"}
      ]),
      _rule(".m.rule.is_room_mention", [
        "notify",
        {"set_tweak": "highlight"}
      ]),
      _rule(".m.rule.roomnotif", [
        "notify",
        {"set_tweak": "highlight"}
      ]),
      _rule(".m.rule.tombstone", [
        "notify",
        {"set_tweak": "highlight"}
      ]),
    ], override),
    "content": merge([
      _rule(
          ".m.rule.contains_user_name",
          [
            "notify",
            _sound,
            {"set_tweak": "highlight"}
          ],
          pattern: "khan"),
    ], content),
    "room": const [],
    "sender": const [],
    "underride": merge([
      _rule(".m.rule.call", [
        "notify",
        {"set_tweak": "sound", "value": "ring"}
      ]),
      _rule(".m.rule.encrypted_room_one_to_one", ["notify", _sound]),
      _rule(".m.rule.room_one_to_one", ["notify", _sound]),
      _rule(".m.rule.message", ["notify"]),
      _rule(".m.rule.encrypted", ["notify"]),
    ], underride),
  });
}

void main() {
  group("the spec's defaults", () {
    final levels = PushRuleLevels(_defaults());

    test("one-to-one chats are noisy, group chats on", () {
      expect(levels.levelOf(PushRuleRows.oneToOne), PushRuleLevel.noisy);
      expect(
          levels.levelOf(PushRuleRows.encryptedOneToOne), PushRuleLevel.noisy);
      expect(levels.levelOf(PushRuleRows.groupChats), PushRuleLevel.on);
      expect(
          levels.levelOf(PushRuleRows.encryptedGroupChats), PushRuleLevel.on);
    });

    test("mentions are noisy, @room on", () {
      expect(levels.levelOf(PushRuleRows.mentions), PushRuleLevel.noisy);
      expect(levels.levelOf(PushRuleRows.roomMentions), PushRuleLevel.on);
    });

    test("invites and calls are noisy, bots off, room upgrades on", () {
      expect(levels.levelOf(PushRuleRows.invites), PushRuleLevel.noisy);
      expect(levels.levelOf(PushRuleRows.calls), PushRuleLevel.noisy);
      expect(levels.levelOf(PushRuleRows.bots), PushRuleLevel.off);
      expect(levels.levelOf(PushRuleRows.roomUpgrades), PushRuleLevel.on);
    });

    test("the user-name rule is a mention, not a keyword", () {
      expect(levels.keywords, isEmpty);
      expect(levels.levelOf(PushRuleRows.keywords), isNull);
    });
  });

  test("a message rule without actions is off", () {
    final levels = PushRuleLevels(
        _defaults(underride: [_rule(".m.rule.message", const [])]));
    expect(levels.levelOf(PushRuleRows.groupChats), PushRuleLevel.off);
  });

  test("a disabled mention rule is off", () {
    final levels = PushRuleLevels(_defaults(override: [
      _rule(".m.rule.is_user_mention", ["notify"], enabled: false),
      _rule(".m.rule.contains_display_name", ["notify"], enabled: false),
    ], content: [
      _rule(".m.rule.contains_user_name", ["notify"],
          enabled: false, pattern: "khan"),
    ]));
    expect(levels.levelOf(PushRuleRows.mentions), PushRuleLevel.off);
  });

  test("rules set apart in another app show no level", () {
    final levels = PushRuleLevels(_defaults(override: [
      _rule(".m.rule.contains_display_name", ["notify"]),
    ]));
    expect(levels.levelOf(PushRuleRows.nameMentions), isNull);
  });

  test("a tag and a name in the text are separate rows", () {
    final levels = PushRuleLevels(_defaults(override: [
      _rule(".m.rule.is_user_mention", ["notify"]),
      _rule(".m.rule.contains_display_name", ["notify"], enabled: false),
    ], content: [
      _rule(".m.rule.contains_user_name", ["notify"],
          enabled: false, pattern: "khan"),
    ]));
    expect(levels.levelOf(PushRuleRows.mentions), PushRuleLevel.on);
    expect(levels.levelOf(PushRuleRows.nameMentions), PushRuleLevel.off);
    expect(levels.rulesOf(PushRuleRows.mentions).single.$2.ruleId,
        ".m.rule.is_user_mention");
  });

  test("bots are on when notices aren't suppressed", () {
    final levels = PushRuleLevels(_defaults(override: [
      _rule(".m.rule.suppress_notices", const [], enabled: false)
    ]));
    expect(levels.levelOf(PushRuleRows.bots), PushRuleLevel.on);
  });

  test("a server without a rule leaves it out of the row", () {
    final levels = PushRuleLevels(matrix.PushRuleSet.fromJson({
      "override": [
        _rule(".m.rule.contains_display_name", ["notify"])
      ],
      "underride": const [],
    }));
    expect(levels.rulesOf(PushRuleRows.nameMentions).length, 1);
    expect(levels.levelOf(PushRuleRows.nameMentions), PushRuleLevel.on);
    expect(levels.rulesOf(PushRuleRows.mentions), isEmpty);
    expect(levels.rulesOf(PushRuleRows.groupChats), isEmpty);
  });

  test("keywords are the account's own content rules", () {
    final levels = PushRuleLevels(_defaults(content: [
      _rule(
          "lunch",
          [
            "notify",
            _sound,
            {"set_tweak": "highlight"}
          ],
          isDefault: false,
          pattern: "lunch"),
      _rule(
          "deploy",
          [
            "notify",
            _sound,
            {"set_tweak": "highlight"}
          ],
          isDefault: false,
          pattern: "deploy"),
    ]));
    expect(levels.keywords.map((r) => r.pattern), ["lunch", "deploy"]);
    expect(levels.levelOf(PushRuleRows.keywords), PushRuleLevel.noisy);
  });

  group("each level reads back as itself", () {
    final rows = [
      ...PushRuleRows.messages,
      ...PushRuleRows.mentionsAndKeywords,
      ...PushRuleRows.other,
    ];
    for (final row in rows) {
      for (final level in PushRuleLevel.values) {
        test("${row.id} ${level.name}", () {
          final stored = row.store(level);
          final rule = matrix.PushRule(
              ruleId: "x",
              default$: true,
              enabled: stored.enabled,
              actions: stored.actions);
          expect(row.levelOf(rule), level);
        });
      }
    }
  });

  test("noisy mentions highlight; noisy messages don't", () {
    bool highlights(List<Object?> actions) =>
        actions.any((a) => a is Map && a["set_tweak"] == "highlight");
    expect(highlights(PushRuleRows.mentions.store(PushRuleLevel.noisy).actions),
        isTrue);
    expect(
        highlights(PushRuleRows.groupChats.store(PushRuleLevel.noisy).actions),
        isFalse);
  });

  test("noisy calls ring", () {
    expect(
        PushRuleRows.calls
            .store(PushRuleLevel.noisy)
            .actions
            .any((a) => a is Map && a["value"] == "ring"),
        isTrue);
  });

  test("off keeps a message rule enabled, as Element does", () {
    final off = PushRuleRows.groupChats.store(PushRuleLevel.off);
    expect(off.enabled, isTrue);
    expect(off.actions, isEmpty);
    expect(PushRuleRows.mentions.store(PushRuleLevel.off).enabled, isFalse);
  });
}
