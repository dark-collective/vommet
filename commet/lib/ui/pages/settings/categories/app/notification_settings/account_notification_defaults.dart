import 'dart:async';

import 'package:collection/collection.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/name_mention_rules.dart';
import 'package:commet/client/matrix/push_rule_levels.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:intl/intl.dart';

/// Vommet: the account-wide notification defaults (Matrix push rules), which
/// Vommet didn't show at all. A room left at its default follows these, so
/// with "Messages in group chats" off in another client a room said "All
/// Messages" here but never notified. Changes apply to the account on every
/// device and app, so the panel says so.
///
/// Vommet issue 719: an Off/On/Noisy grid over the same rules Element's
/// settings show, with the account's keywords. It shows the rules as they
/// are; a row whose rules were set apart in another app shows no level.
class AccountNotificationDefaults extends StatefulWidget {
  const AccountNotificationDefaults({super.key});

  @override
  State<AccountNotificationDefaults> createState() =>
      _AccountNotificationDefaultsState();
}

String _rowLabel(PushRuleRow row) => switch (row.id) {
      "oneToOne" => accountNotifyOneToOne,
      "encryptedOneToOne" => accountNotifyEncryptedOneToOne,
      "groupChats" => accountNotifyGroupChats,
      "encryptedGroupChats" => accountNotifyEncryptedGroupChats,
      "mentions" => accountNotifyMentions,
      "nameMentions" => accountNotifyNameMentions,
      "roomMentions" => accountNotifyRoomMentions,
      "keywords" => accountNotifyKeywords,
      "invites" => accountNotifyInvites,
      "calls" => accountNotifyCalls,
      "bots" => accountNotifyBots,
      "roomUpgrades" => accountNotifyRoomUpgrades,
      _ => row.id,
    };

String? _rowSubtitle(PushRuleRow row) => switch (row.id) {
      "mentions" => accountNotifyMentionsExplain,
      "nameMentions" => accountNotifyNameMentionsExplain,
      _ => null,
    };

class _AccountNotificationDefaultsState
    extends State<AccountNotificationDefaults> {
  final List<StreamSubscription> subs = [];

  /// Choices made here, until the account's rules come back in sync.
  final Map<String, PushRuleLevel> pending = {};

  /// Keyword fields, one per account.
  final Map<String, TextEditingController> keywordFields = {};

  List<MatrixClient> get clients =>
      clientManager?.clients.whereType<MatrixClient>().toList() ?? [];

  @override
  void initState() {
    super.initState();
    for (final c in clients) {
      subs.add(c.getMatrixClient().onSync.stream.where((s) {
        return s.accountData?.any((e) => e.type == "m.push_rules") == true;
      }).listen((_) {
        if (mounted) setState(() => pending.clear());
      }));
    }
  }

  @override
  void dispose() {
    for (final s in subs) {
      s.cancel();
    }
    for (final f in keywordFields.values) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> _set(MatrixClient client, PushRuleRow row, PushRuleLevel level,
      PushRuleLevels levels) async {
    final mx = client.getMatrixClient();
    final key = "${mx.userID}${row.id}";
    setState(() => pending[key] = level);
    try {
      if (row == PushRuleRows.nameMentions) {
        await NameMentionRules.setLevel(mx, levels, level,
            displayName: client.self?.displayName);
        return;
      }
      final stored = row.store(level);
      for (final (kind, rule) in levels.rulesOf(row)) {
        // Off disables a rule and leaves its actions, as Element does.
        if (stored.enabled) {
          await mx.setPushRuleActions(kind, rule.ruleId, stored.actions);
        }
        if (rule.enabled != stored.enabled) {
          await mx.setPushRuleEnabled(kind, rule.ruleId, stored.enabled);
        }
      }
    } catch (e, s) {
      Log.onError(e, s,
          content: "Couldn't change the account's notification defaults");
      if (mounted) setState(() => pending.remove(key));
    }
  }

  Future<void> _addKeyword(matrix.Client mx, PushRuleLevels levels) async {
    final field = keywordFields[mx.userID];
    final keyword = field?.text.trim() ?? "";
    if (keyword.isEmpty) return;
    if (levels.keywords.any((r) => r.pattern == keyword)) {
      field?.clear();
      return;
    }
    // A new keyword takes the keywords' level; the first one is Noisy, like
    // a mention.
    final level = levels.levelOf(PushRuleRows.keywords) ?? PushRuleLevel.noisy;
    final stored = PushRuleRows.keywords.store(level);
    try {
      await mx.setPushRule(matrix.PushRuleKind.content, keyword, stored.actions,
          pattern: keyword);
      if (!stored.enabled) {
        await mx.setPushRuleEnabled(
            matrix.PushRuleKind.content, keyword, false);
      }
      field?.clear();
    } catch (e, s) {
      Log.onError(e, s, content: "Couldn't add a notification keyword");
    }
  }

  Future<void> _removeKeyword(matrix.Client mx, matrix.PushRule rule) async {
    try {
      await mx.deletePushRule(matrix.PushRuleKind.content, rule.ruleId);
    } catch (e, s) {
      Log.onError(e, s, content: "Couldn't remove a notification keyword");
    }
  }

  bool _masterOn(matrix.Client mx) =>
      mx.globalPushRules?.override
          ?.firstWhereOrNull((r) => r.ruleId == ".m.rule.master")
          ?.enabled ==
      true;

  static const double _column = 56;

  Widget _header(BuildContext context, String title) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 2),
        child: Row(children: [
          Expanded(child: tiamat.Text.labelEmphasised(title)),
          for (final l in [
            accountNotifyLevelOff,
            accountNotifyLevelOn,
            accountNotifyLevelNoisy
          ])
            SizedBox(
                width: _column, child: Center(child: tiamat.Text.labelLow(l))),
        ]),
      );

  Widget _row(BuildContext context, MatrixClient client, PushRuleRow row,
      PushRuleLevels levels) {
    final mx = client.getMatrixClient();
    final level = pending["${mx.userID}${row.id}"] ?? levels.levelOf(row);
    final subtitle = _rowSubtitle(row);
    return RadioGroup<PushRuleLevel>(
      groupValue: level,
      onChanged: (l) {
        if (l != null && l != level) _set(client, row, l, levels);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                tiamat.Text.label(_rowLabel(row)),
                if (subtitle != null) tiamat.Text.labelLow(subtitle),
                if (level == null) tiamat.Text.labelLow(accountNotifyMixed),
              ],
            ),
          ),
          for (final l in PushRuleLevel.values)
            SizedBox(
              width: _column,
              child: Radio<PushRuleLevel>(value: l),
            ),
        ]),
      ),
    );
  }

  Widget _keywords(
      BuildContext context, matrix.Client mx, PushRuleLevels levels) {
    final field =
        keywordFields.putIfAbsent(mx.userID ?? "", TextEditingController.new);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (levels.keywords.isNotEmpty)
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final rule in levels.keywords)
                InputChip(
                  label: Text(rule.pattern ?? rule.ruleId),
                  deleteButtonTooltipMessage: accountNotifyRemoveKeyword,
                  onDeleted: () => _removeKeyword(mx, rule),
                ),
            ]),
          TextField(
            controller: field,
            decoration: InputDecoration(
              hintText: accountNotifyAddKeyword,
              suffixIcon: IconButton(
                icon: const Icon(Icons.add),
                tooltip: accountNotifyAddKeywordButton,
                onPressed: () => _addKeyword(mx, levels),
              ),
            ),
            onSubmitted: (_) => _addKeyword(mx, levels),
          ),
        ],
      ),
    );
  }

  List<Widget> _section(BuildContext context, MatrixClient client, String title,
      List<PushRuleRow> rows, PushRuleLevels levels) {
    final shown = [
      for (final row in rows)
        if (row.offWithoutRules || levels.rulesOf(row).isNotEmpty) row,
    ];
    final keywords = rows.contains(PushRuleRows.keywords);
    if (shown.isEmpty && !keywords) return const [];
    return [
      _header(context, title),
      for (final row in shown) _row(context, client, row, levels),
      if (keywords) _keywords(context, client.getMatrixClient(), levels),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final list = clients;
    if (list.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
          child: tiamat.Text.labelLow(accountNotifyDefaultsExplain),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: tiamat.Text.labelLow(accountNotifyLevelsExplain),
        ),
        for (final c in list) ...[
          if (list.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 2),
              child: tiamat.Text.labelEmphasised(
                  c.self?.displayName ?? c.getMatrixClient().userID ?? ""),
            ),
          if (_masterOn(c.getMatrixClient()))
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(spacing: 8, children: [
                Icon(Icons.notifications_off,
                    color: Theme.of(context).colorScheme.error),
                Expanded(child: tiamat.Text.label(accountNotifyMasterOff)),
                tiamat.Button(
                  text: accountNotifyTurnOn,
                  onTap: () => c.getMatrixClient().setPushRuleEnabled(
                      matrix.PushRuleKind.override, ".m.rule.master", false),
                ),
              ]),
            ),
          if (c.getMatrixClient().globalPushRules case final rules?) ...[
            ..._section(context, c, accountNotifyMessages,
                PushRuleRows.messages, PushRuleLevels(rules)),
            ..._section(context, c, accountNotifyMentionsKeywords,
                PushRuleRows.mentionsAndKeywords, PushRuleLevels(rules)),
            ..._section(context, c, accountNotifyOther, PushRuleRows.other,
                PushRuleLevels(rules)),
          ],
        ],
      ],
    );
  }
}

String get accountNotifyLevelOff => Intl.message("Off",
    name: "accountNotifyLevelOff",
    desc:
        "Column header: the setting doesn't notify, it only marks the room unread");

String get accountNotifyLevelOn => Intl.message("On",
    name: "accountNotifyLevelOn",
    desc: "Column header: the setting notifies silently");

String get accountNotifyLevelNoisy => Intl.message("Noisy",
    name: "accountNotifyLevelNoisy",
    desc: "Column header: the setting notifies with a sound");

String get accountNotifyLevelsExplain => Intl.message(
    "Off only marks the room unread. On notifies silently, with a gray badge. Noisy plays a sound and shows a red badge.",
    name: "accountNotifyLevelsExplain",
    desc:
        "Explains the Off, On and Noisy columns of the account notification settings");

String get accountNotifyMixed => Intl.message("Set separately in another app",
    name: "accountNotifyMixed",
    desc:
        "Shown under an account notification setting whose rules have different levels");

String get accountNotifyMessages => Intl.message("Messages",
    name: "accountNotifyMessages",
    desc: "Heading of the account notification settings for messages");

String get accountNotifyMentionsKeywords => Intl.message("Mentions & keywords",
    name: "accountNotifyMentionsKeywords",
    desc:
        "Heading of the account notification settings for mentions and keywords");

String get accountNotifyOther => Intl.message("Other",
    name: "accountNotifyOther",
    desc: "Heading of the other account notification settings");

String get accountNotifyOneToOne => Intl.message("One-to-one chats",
    name: "accountNotifyOneToOne",
    desc: "Account notification setting for messages in rooms with two people");

String get accountNotifyEncryptedOneToOne => Intl.message(
    "Encrypted one-to-one chats",
    name: "accountNotifyEncryptedOneToOne",
    desc:
        "Account notification setting for encrypted messages in rooms with two people");

String get accountNotifyGroupChats => Intl.message("Group chats",
    name: "accountNotifyGroupChats",
    desc:
        "Account notification setting for messages in rooms with more than two people");

String get accountNotifyEncryptedGroupChats => Intl.message(
    "Encrypted group chats",
    name: "accountNotifyEncryptedGroupChats",
    desc:
        "Account notification setting for encrypted messages in rooms with more than two people");

String get accountNotifyMentions => Intl.message("When someone tags me",
    name: "accountNotifyMentions",
    desc:
        "Account notification setting for messages that tag the user with a mention pill");

String get accountNotifyMentionsExplain => Intl.message(
    "A mention pill of your account",
    name: "accountNotifyMentionsExplain",
    desc:
        "Under the account notification setting for being tagged: what counts as a tag");

String get accountNotifyNameMentions => Intl.message("My name in a message",
    name: "accountNotifyNameMentions",
    desc:
        "Account notification setting for messages whose text contains the user's name");

String get accountNotifyNameMentionsExplain => Intl.message(
    "Your username or display name in the text, without a tag",
    name: "accountNotifyNameMentionsExplain",
    desc:
        "Under the account notification setting for the user's name in a message's text");

String get accountNotifyRoomMentions => Intl.message("@room",
    name: "accountNotifyRoomMentions",
    desc:
        "Account notification setting for messages that mention the whole room");

String get accountNotifyKeywords => Intl.message("Keywords",
    name: "accountNotifyKeywords",
    desc:
        "Account notification setting for messages that contain one of the user's keywords");

String get accountNotifyAddKeyword => Intl.message("Add a keyword…",
    name: "accountNotifyAddKeyword",
    desc: "Hint of the field that adds a notification keyword");

String get accountNotifyAddKeywordButton => Intl.message("Add keyword",
    name: "accountNotifyAddKeywordButton",
    desc: "Tooltip of the button that adds a notification keyword");

String get accountNotifyRemoveKeyword => Intl.message("Remove keyword",
    name: "accountNotifyRemoveKeyword",
    desc: "Tooltip of the button that removes a notification keyword");

String get accountNotifyInvites => Intl.message("Invited to a room",
    name: "accountNotifyInvites",
    desc: "Account notification setting for room invites");

String get accountNotifyCalls => Intl.message("Call invitations",
    name: "accountNotifyCalls",
    desc: "Account notification setting for incoming calls");

String get accountNotifyBots => Intl.message("Messages sent by bots",
    name: "accountNotifyBots",
    desc: "Account notification setting for notices sent by bots");

String get accountNotifyRoomUpgrades => Intl.message("Room upgrades",
    name: "accountNotifyRoomUpgrades",
    desc: "Account notification setting for rooms being upgraded");

String get accountNotifyDefaultsExplain => Intl.message(
    "Your account's defaults, for rooms left at their default setting. They apply to the account on all your devices and apps, Element included.",
    name: "accountNotifyDefaultsExplain",
    desc: "Explanation above the account notification defaults");

String get accountNotifyMasterOff => Intl.message(
    "All notifications are switched off for this account.",
    name: "accountNotifyMasterOff",
    desc:
        "Shown when the account's master push rule disables all notifications");

String get accountNotifyTurnOn => Intl.message("Turn on",
    name: "accountNotifyTurnOn",
    desc: "Button that turns account notifications back on");
