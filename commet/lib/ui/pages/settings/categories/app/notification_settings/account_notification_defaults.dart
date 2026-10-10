import 'dart:async';

import 'package:collection/collection.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet: the account-wide notification defaults (Matrix push rules), which
/// Vommet didn't show at all. A room left at its default follows these, so
/// with "Messages in group chats" off in another client a room said "All
/// Messages" here but never notified. Changes apply to the account on every
/// device and app, so the panel says so.
class AccountNotificationDefaults extends StatefulWidget {
  const AccountNotificationDefaults({super.key});

  @override
  State<AccountNotificationDefaults> createState() =>
      _AccountNotificationDefaultsState();
}

class _Toggle {
  const _Toggle(this.label, this.description, this.ruleIds, this.onActions);
  final String label;
  final String description;
  final List<String> ruleIds;
  final List<Object?> onActions;
}

const _toggles = [
  _Toggle(
      "Messages in group chats",
      "Every new message in rooms with more than two people.",
      [".m.rule.message", ".m.rule.encrypted"],
      ["notify"]),
  _Toggle("Direct messages", "Every new message in one-to-one chats.", [
    ".m.rule.room_one_to_one",
    ".m.rule.encrypted_room_one_to_one"
  ], [
    "notify",
    {"set_tweak": "sound", "value": "default"}
  ]),
];

class _AccountNotificationDefaultsState
    extends State<AccountNotificationDefaults> {
  final List<StreamSubscription> subs = [];

  /// Choices made here, until the account's rules come back in sync.
  final Map<String, bool> pending = {};

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
    super.dispose();
  }

  static bool _notifies(matrix.PushRule r) =>
      r.enabled && r.actions.contains("notify");

  bool? _state(matrix.Client mx, _Toggle t) {
    final key = "${mx.userID}${t.label}";
    if (pending.containsKey(key)) return pending[key];
    final rules = mx.globalPushRules?.underride ?? const [];
    final found = [
      for (final id in t.ruleIds) rules.firstWhereOrNull((r) => r.ruleId == id)
    ].whereType<matrix.PushRule>().toList();
    if (found.isEmpty) return null;
    return found.every(_notifies);
  }

  Future<void> _set(matrix.Client mx, _Toggle t, bool on) async {
    setState(() => pending["${mx.userID}${t.label}"] = on);
    try {
      final rules = mx.globalPushRules?.underride ?? const [];
      for (final id in t.ruleIds) {
        final rule = rules.firstWhereOrNull((r) => r.ruleId == id);
        if (rule == null) continue;
        await mx.setPushRuleActions(
            matrix.PushRuleKind.underride, id, on ? t.onActions : const []);
        if (!rule.enabled) {
          await mx.setPushRuleEnabled(matrix.PushRuleKind.underride, id, true);
        }
      }
    } catch (e, s) {
      Log.onError(e, s,
          content: "Couldn't change the account's notification defaults");
      if (mounted) setState(() => pending.remove("${mx.userID}${t.label}"));
    }
  }

  bool _masterOn(matrix.Client mx) =>
      mx.globalPushRules?.override
          ?.firstWhereOrNull((r) => r.ruleId == ".m.rule.master")
          ?.enabled ==
      true;

  @override
  Widget build(BuildContext context) {
    final list = clients;
    if (list.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: tiamat.Text.labelLow(
              "Your account's defaults, for rooms left at their default setting. "
              "They apply to the account on all your devices and apps, "
              "Element included."),
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
                Expanded(
                    child: tiamat.Text.label(
                        "All notifications are switched off for this account.")),
                tiamat.Button(
                  text: "Turn on",
                  onTap: () => c.getMatrixClient().setPushRuleEnabled(
                      matrix.PushRuleKind.override, ".m.rule.master", false),
                ),
              ]),
            ),
          for (final t in _toggles)
            if (_state(c.getMatrixClient(), t) case final on?)
              SwitchListTile(
                title: tiamat.Text.label(t.label),
                subtitle: tiamat.Text.labelLow(t.description),
                value: on,
                onChanged: (v) => _set(c.getMatrixClient(), t, v),
              ),
        ],
      ],
    );
  }
}
