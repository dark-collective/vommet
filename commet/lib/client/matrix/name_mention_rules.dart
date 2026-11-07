import 'package:commet/client/matrix/push_rule_levels.dart';
import 'package:commet/debug/log.dart';
import 'package:matrix/matrix.dart' as matrix;

/// Vommet: "My name in a message", your user name or display name in a
/// message's text without a tag. Servers that keep the legacy rules
/// (`.m.rule.contains_display_name`, `.m.rule.contains_user_name`) store it
/// there. Tuwunel removes those rules from every account (MSC4210) and
/// refuses `.m.rule.*` ids from clients, so there the setting is Off until
/// turned on, which adds Vommet's own content rules: one for the user name
/// and one for the display name, with the level's actions. Off removes them.
///
/// They are content rules, like keywords, so they still match a message
/// that has `m.mentions` (only the legacy ids are skipped then, Vommet issue
/// 666), and the keyword list leaves them out.
class NameMentionRules {
  static const prefix = "im.nether.vommet.name.";
  static const userNameId = "${prefix}username";
  static const displayNameId = "${prefix}displayname";

  static const legacyIds = [
    ".m.rule.contains_display_name",
    ".m.rule.contains_user_name",
  ];
  static const ownIds = [userNameId, displayNameId];

  /// Whether [ruleId] is one of Vommet's name rules.
  static bool isOwn(String ruleId) => ruleId.startsWith(prefix);

  /// [text] as a push rule glob that matches it: `*`, `?`, `[` and `]` are
  /// glob syntax, so each becomes `?` (any one character).
  static String globFor(String text) =>
      text.trim().replaceAll(RegExp(r"[*?\[\]]"), "?");

  /// The local part of [userId] (`@name:server` -> `name`).
  static String? localpart(String? userId) {
    if (userId == null || !userId.startsWith("@")) return null;
    final colon = userId.indexOf(":");
    final name = userId.substring(1, colon < 0 ? userId.length : colon);
    return name.isEmpty ? null : name;
  }

  /// The patterns of Vommet's rules for this account: rule id -> pattern.
  /// No display name, no display-name rule.
  static Map<String, String> patterns(
      {required String? userId, required String? displayName}) {
    final user = localpart(userId);
    final name = displayName?.trim() ?? "";
    return {
      if (user != null) userNameId: globFor(user),
      if (name.isNotEmpty) displayNameId: globFor(name),
    };
  }

  /// Sets the row to [level] on [mx]'s account.
  static Future<void> setLevel(
      matrix.Client mx, PushRuleLevels levels, PushRuleLevel level,
      {String? displayName}) async {
    final stored = PushRuleRows.nameMentions.store(level);
    final legacy = legacyIds.map(levels.find).nonNulls.toList();
    final own = ownIds.map(levels.find).nonNulls.toList();

    if (legacy.isNotEmpty) {
      // The server keeps the legacy rules: set those, as Element does, and
      // drop any rules of ours so the two don't disagree.
      for (final (kind, rule) in legacy) {
        if (stored.enabled) {
          await mx.setPushRuleActions(kind, rule.ruleId, stored.actions);
        }
        if (rule.enabled != stored.enabled) {
          await mx.setPushRuleEnabled(kind, rule.ruleId, stored.enabled);
        }
      }
      for (final (kind, rule) in own) {
        await mx.deletePushRule(kind, rule.ruleId);
      }
      return;
    }

    if (!stored.enabled) {
      for (final (kind, rule) in own) {
        await mx.deletePushRule(kind, rule.ruleId);
      }
      return;
    }

    final wanted = patterns(userId: mx.userID, displayName: displayName);
    for (final MapEntry(key: id, value: pattern) in wanted.entries) {
      await mx.setPushRule(matrix.PushRuleKind.content, id, stored.actions,
          pattern: pattern);
      final existing = levels.find(id);
      if (existing != null && !existing.$2.enabled) {
        await mx.setPushRuleEnabled(matrix.PushRuleKind.content, id, true);
      }
    }
  }

  static final Expando<String> _following = Expando();

  /// Keeps the display-name rule's pattern on [displayName] after a change
  /// of name (best effort; nothing to do while the setting is Off).
  static Future<void> followDisplayName(
      matrix.Client mx, String? displayName) async {
    final name = displayName?.trim() ?? "";
    final rules = mx.globalPushRules;
    if (name.isEmpty || rules == null) return;
    final levels = PushRuleLevels(rules);
    // The setting is on when the user-name rule is there; a display-name
    // rule that's missing (no name when it was turned on) is added.
    final source = levels.find(displayNameId) ?? levels.find(userNameId);
    if (source == null) return;
    final (_, rule) = source;
    final pattern = globFor(name);
    if (rule.ruleId == displayNameId && rule.pattern == pattern) return;
    if (_following[mx] == pattern) return;
    _following[mx] = pattern;
    try {
      await mx.setPushRule(
          matrix.PushRuleKind.content, displayNameId, rule.actions,
          pattern: pattern);
      if (!rule.enabled) {
        await mx.setPushRuleEnabled(
            matrix.PushRuleKind.content, displayNameId, false);
      }
    } catch (e, s) {
      Log.onError(e, s,
          content: "Couldn't update the display name notification rule");
    } finally {
      _following[mx] = null;
    }
  }
}
