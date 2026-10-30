import 'package:commet/client/matrix/name_mention_rules.dart';
import 'package:matrix/matrix.dart' as matrix;

/// Vommet issue 719: a notification setting's level, as Element's settings
/// show it: Off (only marks the room unread), On (a silent notification,
/// gray badge) or Noisy (a notification with a sound, red badge).
enum PushRuleLevel { off, on, noisy }

/// How a row's levels are stored on its rules (Element's
/// VectorPushRulesDefinitions, so both apps read and write the same rules).
enum PushRuleStyle {
  /// Message rules (underride): Off keeps the rule enabled without actions.
  message,

  /// Mentions, keywords, @room and room upgrades: Off disables the rule;
  /// Noisy also highlights (the red badge).
  highlight,

  /// Invites and calls: Off disables the rule; Noisy plays a sound.
  alert,

  /// Bots (`.m.rule.suppress_notices`, which silences bot notices): On
  /// disables it so bots notify like anyone else.
  suppress,
}

const _sound = {"set_tweak": "sound", "value": "default"};
const _ring = {"set_tweak": "sound", "value": "ring"};
const _highlight = {"set_tweak": "highlight"};

/// A row of the account's Off/On/Noisy grid and the predefined rules behind
/// it.
class PushRuleRow {
  const PushRuleRow(this.id, this.style, this.ruleIds,
      {this.ring = false, this.offWithoutRules = false});

  /// Names the row (and its label, see the settings page).
  final String id;
  final PushRuleStyle style;

  /// The rules the row sets together. A server without one of them (an
  /// older spec version) just has fewer.
  final List<String> ruleIds;

  /// Noisy rings instead of the default sound (calls).
  final bool ring;

  /// Shown as Off when the account has none of its rules (Vommet makes its
  /// own when turned on), instead of being left out.
  final bool offWithoutRules;

  /// The actions and enabled state that store [level].
  ({bool enabled, List<Object?> actions}) store(PushRuleLevel level) =>
      switch ((style, level)) {
        (PushRuleStyle.message, PushRuleLevel.off) => (
            enabled: true,
            actions: const []
          ),
        (PushRuleStyle.message, PushRuleLevel.on) => (
            enabled: true,
            actions: const ["notify"]
          ),
        (PushRuleStyle.message, PushRuleLevel.noisy) => (
            enabled: true,
            actions: const ["notify", _sound]
          ),
        (PushRuleStyle.highlight, PushRuleLevel.off) => (
            enabled: false,
            actions: const ["notify"]
          ),
        (PushRuleStyle.highlight, PushRuleLevel.on) => (
            enabled: true,
            actions: const ["notify"]
          ),
        (PushRuleStyle.highlight, PushRuleLevel.noisy) => (
            enabled: true,
            actions: const ["notify", _highlight, _sound]
          ),
        (PushRuleStyle.alert, PushRuleLevel.off) => (
            enabled: false,
            actions: const ["notify"]
          ),
        (PushRuleStyle.alert, PushRuleLevel.on) => (
            enabled: true,
            actions: const ["notify"]
          ),
        (PushRuleStyle.alert, PushRuleLevel.noisy) => (
            enabled: true,
            actions: ["notify", ring ? _ring : _sound]
          ),
        (PushRuleStyle.suppress, PushRuleLevel.off) => (
            enabled: true,
            actions: const []
          ),
        (PushRuleStyle.suppress, PushRuleLevel.on) => (
            enabled: false,
            actions: const []
          ),
        (PushRuleStyle.suppress, PushRuleLevel.noisy) => (
            enabled: true,
            actions: const ["notify", _sound]
          ),
      };

  /// The level [rule] stores under this row's style.
  PushRuleLevel levelOf(matrix.PushRule rule) {
    final notifies = rule.actions.contains("notify");
    final sound =
        rule.actions.any((a) => a is Map && a["set_tweak"] == "sound");
    if (style == PushRuleStyle.suppress) {
      if (!rule.enabled) return PushRuleLevel.on;
      if (!notifies) return PushRuleLevel.off;
      return sound ? PushRuleLevel.noisy : PushRuleLevel.on;
    }
    if (!rule.enabled || !notifies) return PushRuleLevel.off;
    return sound ? PushRuleLevel.noisy : PushRuleLevel.on;
  }
}

/// The grid's rows, in the mockup's order (Vommet issue 719).
class PushRuleRows {
  static const oneToOne = PushRuleRow(
      "oneToOne", PushRuleStyle.message, [".m.rule.room_one_to_one"]);
  static const encryptedOneToOne = PushRuleRow("encryptedOneToOne",
      PushRuleStyle.message, [".m.rule.encrypted_room_one_to_one"]);
  static const groupChats =
      PushRuleRow("groupChats", PushRuleStyle.message, [".m.rule.message"]);
  static const encryptedGroupChats = PushRuleRow(
      "encryptedGroupChats", PushRuleStyle.message, [".m.rule.encrypted"]);

  /// Tagged with a mention pill (`m.mentions`).
  static const mentions = PushRuleRow(
      "mentions", PushRuleStyle.highlight, [".m.rule.is_user_mention"]);

  /// Your user name or display name in a message's text, without a tag: the
  /// legacy rules where the server keeps them, else Vommet's own content
  /// rules ([NameMentionRules]; Tuwunel removes the legacy ones, MSC4210).
  static const nameMentions = PushRuleRow(
      "nameMentions",
      PushRuleStyle.highlight,
      [
        ...NameMentionRules.legacyIds,
        ...NameMentionRules.ownIds,
      ],
      offWithoutRules: true);
  static const roomMentions = PushRuleRow(
      "roomMentions",
      PushRuleStyle.highlight,
      [".m.rule.is_room_mention", ".m.rule.roomnotif"]);

  /// The account's own keyword rules ([PushRuleLevels.keywords]); no
  /// predefined ids.
  static const keywords = PushRuleRow("keywords", PushRuleStyle.highlight, []);

  static const invites =
      PushRuleRow("invites", PushRuleStyle.alert, [".m.rule.invite_for_me"]);
  static const calls =
      PushRuleRow("calls", PushRuleStyle.alert, [".m.rule.call"], ring: true);
  static const bots =
      PushRuleRow("bots", PushRuleStyle.suppress, [".m.rule.suppress_notices"]);
  static const roomUpgrades = PushRuleRow(
      "roomUpgrades", PushRuleStyle.highlight, [".m.rule.tombstone"]);

  static const messages = [
    oneToOne,
    encryptedOneToOne,
    groupChats,
    encryptedGroupChats
  ];
  static const mentionsAndKeywords = [
    mentions,
    nameMentions,
    roomMentions,
    keywords
  ];
  static const other = [invites, calls, bots, roomUpgrades];
}

/// Reads and writes the grid on an account's push rules.
class PushRuleLevels {
  PushRuleLevels(this.rules);

  final matrix.PushRuleSet rules;

  static const _kinds = [
    matrix.PushRuleKind.override,
    matrix.PushRuleKind.content,
    matrix.PushRuleKind.room,
    matrix.PushRuleKind.sender,
    matrix.PushRuleKind.underride,
  ];

  List<matrix.PushRule> _ofKind(matrix.PushRuleKind kind) =>
      switch (kind) {
        matrix.PushRuleKind.override => rules.override,
        matrix.PushRuleKind.content => rules.content,
        matrix.PushRuleKind.room => rules.room,
        matrix.PushRuleKind.sender => rules.sender,
        matrix.PushRuleKind.underride => rules.underride,
      } ??
      const [];

  /// [id]'s rule and its kind, or null when the server has no such rule.
  (matrix.PushRuleKind, matrix.PushRule)? find(String id) {
    for (final kind in _kinds) {
      for (final rule in _ofKind(kind)) {
        if (rule.ruleId == id) return (kind, rule);
      }
    }
    return null;
  }

  /// The account's keyword rules: content rules it made itself (the
  /// predefined user-name rule and Vommet's name rules are name mentions).
  List<matrix.PushRule> get keywords => [
        for (final rule in _ofKind(matrix.PushRuleKind.content))
          if (!rule.default$ &&
              !rule.ruleId.startsWith(".") &&
              !NameMentionRules.isOwn(rule.ruleId))
            rule,
      ];

  /// The rules behind [row] that this account has, with their kind.
  List<(matrix.PushRuleKind, matrix.PushRule)> rulesOf(PushRuleRow row) =>
      row == PushRuleRows.keywords
          ? [for (final r in keywords) (matrix.PushRuleKind.content, r)]
          : row.ruleIds.map(find).nonNulls.toList();

  /// [row]'s level: the level all its rules share. Null when its rules
  /// differ (set in another app one by one) or the account has none of them
  /// (Off for a row that makes its own rules).
  PushRuleLevel? levelOf(PushRuleRow row) {
    final rules = rulesOf(row);
    if (rules.isEmpty && row.offWithoutRules) return PushRuleLevel.off;
    final levels = {for (final (_, r) in rules) row.levelOf(r)};
    return levels.length == 1 ? levels.single : null;
  }
}
