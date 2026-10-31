// Vommet issue 631: sets a notification level on many rooms at once, from
// Settings > Notifications ("Apply to rooms I'm in now…") or a space's menu
// (Discord-style space notifications). Asks first with the counts, then runs
// in the background with progress and a list of rooms that failed.

import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/utils/common_strings.dart';
import 'package:commet/utils/space_hierarchy/room_batch_task.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Why a room is left as it is.
enum BulkPushRuleSkip { direct, space, muted, already }

/// The rooms of one account that a bulk change would touch.
class BulkPushRuleAccount {
  BulkPushRuleAccount(this.client);
  final Client client;
  final List<Room> change = [];
}

class BulkPushRulePlan {
  BulkPushRulePlan(this.target);
  final PushRule target;
  final List<BulkPushRuleAccount> accounts = [];
  final Map<BulkPushRuleSkip, int> skipped = {};

  int get total => accounts.fold(0, (n, a) => n + a.change.length);

  /// Whether a room at [current] is changed to [target], or why not.
  /// Direct messages and spaces keep their level; muted rooms stay muted.
  static BulkPushRuleSkip? skipFor(
      {required bool isDirect,
      required bool isSpace,
      required PushRule current,
      required PushRule target}) {
    if (isSpace) return BulkPushRuleSkip.space;
    if (isDirect) return BulkPushRuleSkip.direct;
    if (current == target) return BulkPushRuleSkip.already;
    if (current == PushRule.dontNotify) return BulkPushRuleSkip.muted;
    return null;
  }

  /// Sorts each account's [rooms] into changed and skipped.
  static BulkPushRulePlan build(
      Iterable<(Client, Iterable<Room>)> sources, PushRule target) {
    final plan = BulkPushRulePlan(target);
    for (final (client, rooms) in sources) {
      final account = BulkPushRuleAccount(client);
      final dms = client.getComponent<DirectMessagesComponent>();
      final spaceIds = client.spaces.map((s) => s.identifier).toSet();
      final seen = <String>{};
      for (final room in rooms) {
        if (!seen.add(room.identifier)) continue;
        final skip = skipFor(
            isDirect: dms?.isRoomDirectMessage(room) ?? false,
            isSpace: spaceIds.contains(room.identifier),
            current: room.pushRule,
            target: target);
        if (skip == null) {
          account.change.add(room);
        } else {
          plan.skipped[skip] = (plan.skipped[skip] ?? 0) + 1;
        }
      }
      if (account.change.isNotEmpty) plan.accounts.add(account);
    }
    return plan;
  }
}

class ApplyPushRule {
  static String levelName(PushRule rule) {
    switch (rule) {
      case PushRule.notify:
        return applyPushRuleLevelAll;
      case PushRule.mentionsOnly:
        return applyPushRuleLevelMentions;
      case PushRule.dontNotify:
        return applyPushRuleLevelMute;
    }
  }

  static String get applyPushRuleLevelAll => Intl.message("All Messages",
      name: "applyPushRuleLevelAll",
      desc: "Notification level name in the dialog that changes many rooms");

  static String get applyPushRuleLevelMentions => Intl.message(
      "Mentions & Keywords",
      name: "applyPushRuleLevelMentions",
      desc: "Notification level name in the dialog that changes many rooms");

  static String get applyPushRuleLevelMute => Intl.message("Mute",
      name: "applyPushRuleLevelMute",
      desc: "Notification level name in the dialog that changes many rooms");

  static String applyPushRuleTitle(int count) => Intl.plural(count,
      one: "Change 1 group room?",
      other: "Change $count group rooms?",
      args: [count],
      name: "applyPushRuleTitle",
      desc: "Title of the dialog that sets a notification level on many rooms");

  static String applyPushRuleConfirm(int count) => Intl.plural(count,
      one: "Change 1 room",
      other: "Change $count rooms",
      args: [count],
      name: "applyPushRuleConfirm",
      desc: "Confirm button of the dialog that sets a notification level on "
          "many rooms");

  static String applyPushRuleSetTo(String level) =>
      Intl.message("Set to $level:",
          args: [level],
          name: "applyPushRuleSetTo",
          desc: "Line above the per-account room counts, e.g. 'Set to Mute:'");

  static String applyPushRuleRoomCount(int count) => Intl.plural(count,
      one: "1 room",
      other: "$count rooms",
      args: [count],
      name: "applyPushRuleRoomCount",
      desc: "Number of rooms an account will change");

  static String get applyPushRuleLeftAlone => Intl.message("Left as they are:",
      name: "applyPushRuleLeftAlone",
      desc: "Line above the list of rooms a bulk notification change skips");

  static String applyPushRuleSkipMuted(int count) => Intl.plural(count,
      one: "1 muted room",
      other: "$count muted rooms",
      args: [count],
      name: "applyPushRuleSkipMuted",
      desc: "Skipped by a bulk notification change");

  static String applyPushRuleSkipDirect(int count) => Intl.plural(count,
      one: "1 direct message",
      other: "$count direct messages",
      args: [count],
      name: "applyPushRuleSkipDirect",
      desc: "Skipped by a bulk notification change");

  static String applyPushRuleSkipAlready(int count) => Intl.plural(count,
      one: "1 already at this level",
      other: "$count already at this level",
      args: [count],
      name: "applyPushRuleSkipAlready",
      desc: "Skipped by a bulk notification change");

  static String applyPushRuleNothing(String level) => Intl.message(
      "Every group room is already at $level (muted rooms and direct messages keep their level).",
      args: [level],
      name: "applyPushRuleNothing",
      desc: "Shown when a bulk notification change has no rooms to change");

  static String get applyPushRuleTaskName => Intl.message("notifications",
      name: "applyPushRuleTaskName",
      desc: "Background task label part: 'Updating notifications: 3 of 27'");

  /// Asks with the counts, then changes the rooms in the background (one
  /// task per account). [taskName] names the task, e.g. the space's name.
  static Future<void> confirmAndApply(BuildContext context,
      {required Iterable<(Client, Iterable<Room>)> sources,
      required PushRule target,
      String? taskName}) async {
    final plan = BulkPushRulePlan.build(sources, target);
    final level = levelName(target);

    if (plan.total == 0) {
      await AdaptiveDialog.show(context,
          title: applyPushRuleTitle(0),
          builder: (context) => ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: tiamat.Text.body(applyPushRuleNothing(level)),
              )));
      return;
    }

    final confirmed = await AdaptiveDialog.confirmation(context,
        title: applyPushRuleTitle(plan.total),
        confirmationText: applyPushRuleConfirm(plan.total),
        prompt: applyPushRuleSetTo(level),
        cancelText: CommonStrings.promptCancel,
        customBuilder: (context) => _PlanSummary(plan, level));
    if (confirmed != true) return;

    for (final account in plan.accounts) {
      final rooms = {for (final r in account.change) r.identifier: r};
      final task = RoomBatchTask(
        verb: "Updating",
        doneVerb: "Updated",
        failVerb: "updated",
        spaceName: taskName ?? applyPushRuleTaskName,
        items: [
          for (final r in account.change)
            RoomBatchItem(r.identifier, r.displayName)
        ],
        run: (item) async => rooms[item.roomId]?.setPushRule(target),
        reasonFor: (item, e) => e.toString(),
      );
      backgroundTaskManager.addTask(task);
      unawaited(task.start());
    }
  }
}

class _PlanSummary extends StatelessWidget {
  const _PlanSummary(this.plan, this.level);
  final BulkPushRulePlan plan;
  final String level;

  @override
  Widget build(BuildContext context) {
    final skipped = [
      if ((plan.skipped[BulkPushRuleSkip.muted] ?? 0) > 0)
        ApplyPushRule.applyPushRuleSkipMuted(
            plan.skipped[BulkPushRuleSkip.muted]!),
      if ((plan.skipped[BulkPushRuleSkip.direct] ?? 0) > 0)
        ApplyPushRule.applyPushRuleSkipDirect(
            plan.skipped[BulkPushRuleSkip.direct]!),
      if ((plan.skipped[BulkPushRuleSkip.already] ?? 0) > 0)
        ApplyPushRule.applyPushRuleSkipAlready(
            plan.skipped[BulkPushRuleSkip.already]!),
    ];

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final account in plan.accounts)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(
                      child: tiamat.Text.body(account.client.self?.identifier ??
                          account.client.identifier)),
                  tiamat.Text.body(ApplyPushRule.applyPushRuleRoomCount(
                      account.change.length)),
                ],
              ),
            ),
          if (skipped.isNotEmpty) ...[
            const SizedBox(height: 12),
            tiamat.Text.labelLow(ApplyPushRule.applyPushRuleLeftAlone),
            const SizedBox(height: 4),
            tiamat.Text.body(skipped.join(", ")),
          ],
        ],
      ),
    );
  }
}
