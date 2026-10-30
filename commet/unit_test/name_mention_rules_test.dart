// Vommet: "My name in a message" (Settings › Notifications). Tuwunel removes
// the legacy name rules (MSC4210), so Vommet stores the setting in content
// rules of its own; they aren't keywords.
import 'package:commet/client/matrix/matrix_push_rules.dart';
import 'package:commet/client/matrix/name_mention_rules.dart';
import 'package:commet/client/matrix/push_rule_levels.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;

const _noisy = [
  "notify",
  {"set_tweak": "highlight"},
  {"set_tweak": "sound", "value": "default"},
];

Map<String, Object?> _content(String id, String pattern,
        {List<Object?> actions = _noisy, bool enabled = true}) =>
    {
      "rule_id": id,
      "default": false,
      "enabled": enabled,
      "actions": actions,
      "pattern": pattern,
    };

/// A Tuwunel account: no legacy name rules.
matrix.PushRuleSet _tuwunel({List<Map<String, Object?>> content = const []}) =>
    matrix.PushRuleSet.fromJson({
      "override": [
        {
          "rule_id": ".m.rule.is_user_mention",
          "default": true,
          "enabled": true,
          "actions": _noisy,
          "conditions": const [],
        },
      ],
      "content": content,
      "room": const [],
      "sender": const [],
      "underride": const [],
    });

void main() {
  test("without the legacy rules the row is shown as Off", () {
    final levels = PushRuleLevels(_tuwunel());
    expect(levels.rulesOf(PushRuleRows.nameMentions), isEmpty);
    expect(levels.levelOf(PushRuleRows.nameMentions), PushRuleLevel.off);
    expect(levels.levelOf(PushRuleRows.mentions), PushRuleLevel.noisy);
  });

  test("Vommet's name rules set the row and aren't keywords", () {
    final levels = PushRuleLevels(_tuwunel(content: [
      _content(NameMentionRules.userNameId, "dark"),
      _content(NameMentionRules.displayNameId, "Dark Collective"),
      _content("lunch", "lunch"),
    ]));
    expect(levels.levelOf(PushRuleRows.nameMentions), PushRuleLevel.noisy);
    expect(levels.keywords.map((r) => r.ruleId), ["lunch"]);
    expect(levels.levelOf(PushRuleRows.keywords), PushRuleLevel.noisy);
  });

  test("patterns: the user name's local part and the display name", () {
    expect(
        NameMentionRules.patterns(
            userId: "@dark:nether.im", displayName: " Dark Collective "),
        {
          NameMentionRules.userNameId: "dark",
          NameMentionRules.displayNameId: "Dark Collective",
        });
    expect(
        NameMentionRules.patterns(userId: "@dark:nether.im", displayName: ""),
        {NameMentionRules.userNameId: "dark"});
  });

  test("glob characters in a name match any one character", () {
    expect(NameMentionRules.globFor("*star* [x]?"), "?star? ?x??");
  });

  test("the rules match a name in the text, also with m.mentions", () {
    final rules = _tuwunel(content: [
      _content(NameMentionRules.userNameId, "dark"),
    ]);
    // Vommet issue 666 drops only the legacy ids for messages with
    // m.mentions; Vommet's rules work like keywords.
    final kept = MatrixPushRules.withoutLegacyMentionRules(rules);
    expect(kept.content!.map((r) => r.ruleId),
        contains(NameMentionRules.userNameId));
    expect(MatrixPushRules.legacyMentionRules.any(NameMentionRules.isOwn),
        isFalse);
  });

  test("Off, On and Noisy read back from Vommet's rules", () {
    for (final level in PushRuleLevel.values) {
      final stored = PushRuleRows.nameMentions.store(level);
      if (!stored.enabled) continue; // Off removes the rules
      final levels = PushRuleLevels(_tuwunel(content: [
        _content(NameMentionRules.userNameId, "dark", actions: stored.actions),
      ]));
      expect(levels.levelOf(PushRuleRows.nameMentions), level);
    }
  });
}
