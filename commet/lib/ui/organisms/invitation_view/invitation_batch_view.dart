import 'dart:async';
import 'dart:math' as math;
import 'package:commet/ui/atoms/redaction_scope.dart';
import 'package:commet/main.dart' show backgroundTaskManager;
import 'package:commet/ui/molecules/user_panel.dart';
import 'package:commet/ui/organisms/invitation_view/batch_invite_source.dart';
import 'package:commet/utils/invitations/batch_invite_strings.dart';
import 'package:commet/utils/invitations/invitation_batch.dart';
import 'package:commet/utils/scaled_app.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as t;

final _visibleBatches = <InvitationBatchTask>{};
bool invitationBatchVisible(InvitationBatchTask task) =>
    _visibleBatches.contains(task);
Future<void> showInvitationBatch(
  NavigatorState navigator,
  InvitationBatchTask task,
  Map<String, InvitePerson> people,
) async {
  if (!navigator.mounted || !_visibleBatches.add(task)) return;
  backgroundTaskManager.tasks.update();
  try {
    await showDialog<void>(
      context: navigator.context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: InvitationBatchView(task: task, people: people),
      ),
    );
  } finally {
    _visibleBatches.remove(task);
    backgroundTaskManager.tasks.update();
  }
}

class InvitationBatchCard extends StatelessWidget {
  const InvitationBatchCard(this.task, {super.key});
  final InvitationBatchTask task;
  @override
  Widget build(BuildContext context) => StreamBuilder<void>(
        stream: task.statusChanged,
        builder: (context, _) => ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(task.label, style: Theme.of(context).textTheme.labelLarge),
                if (task.running)
                  LinearProgressIndicator(
                    value: task.total == 0 ? 0 : task.current / task.total,
                  ),
                Wrap(
                  children: [
                    TextButton(
                      onPressed: task.action,
                      child: Text(batchInviteViewResults),
                    ),
                    if (task.running)
                      TextButton(
                        onPressed: task.stopping ? null : task.stop,
                        child: Text(task.stopping
                            ? batchInviteStopping
                            : batchInviteStop),
                      )
                    else
                      TextButton(
                        onPressed: task.dismiss,
                        child: Text(batchInviteDismiss),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
}

class InvitationBatchView extends StatelessWidget {
  const InvitationBatchView({
    required this.task,
    required this.people,
    super.key,
  });
  final InvitationBatchTask task;
  final Map<String, InvitePerson> people;
  String stateLabel(BatchInviteItem item) => switch (item.outcome) {
        InviteOutcome.waiting => batchInviteStateWaiting,
        InviteOutcome.sending => batchInviteStateSending,
        InviteOutcome.sent => item.operation == InviteOperation.history
            ? batchInviteStateShareRecorded
            : batchInviteStateSent,
        InviteOutcome.skipped => batchInviteStateSkipped,
        InviteOutcome.blocked => batchInviteAccessCannotInvite,
        InviteOutcome.failed => batchInviteStateFailed,
        InviteOutcome.unconfirmed => batchInviteStateUnconfirmed,
        InviteOutcome.held => item.inOtherBatch
            ? batchInviteStateOtherBatch
            : batchInviteStateWaitingParent,
        InviteOutcome.canceled => batchInviteReasonNotSent,
      };
  Future<void> confirmUnknown(BuildContext context) async {
    final retry = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(batchInviteRetryUnconfirmedTitle),
        content: Text(batchInviteRetryUnconfirmedBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(batchInviteCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(batchInviteRetryUnconfirmed),
          ),
        ],
      ),
    );
    if (retry == true) await task.retryUnconfirmed();
  }

  bool attention(BatchInviteItem item) => {
        InviteOutcome.failed,
        InviteOutcome.blocked,
        InviteOutcome.unconfirmed,
        InviteOutcome.held,
        InviteOutcome.canceled,
      }.contains(item.outcome);
  List<String> recipientOrder() {
    final ids = task.items.map((i) => i.userId).toSet().toList();
    int priority(String id) =>
        task.items.any((i) => i.userId == id && attention(i))
            ? 0
            : task.items.any(
                    (i) => i.userId == id && i.outcome == InviteOutcome.sending)
                ? 1
                : 2;
    final order = {for (var i = 0; i < ids.length; i++) ids[i]: i};
    ids.sort((a, b) {
      final result = priority(a).compareTo(priority(b));
      return result == 0 ? order[a]!.compareTo(order[b]!) : result;
    });
    return ids;
  }

  Widget recipient(BuildContext context, String id) {
    final policy = RedactionScope.of(context);
    final items = task.items.where((i) => i.userId == id).toList();
    final urgent = items.any(attention);
    final active = items.any((i) => i.outcome == InviteOutcome.sending);
    final count = items
        .where((i) =>
            i.operation == InviteOperation.invite &&
            i.outcome == InviteOutcome.sent)
        .length;
    final issues = items.where(attention).length;
    final ranked = {for (var i = 0; i < items.length; i++) items[i]: i};
    items.sort((a, b) {
      final result = (attention(a) ? 0 : 1).compareTo(attention(b) ? 0 : 1);
      return result == 0 ? ranked[a]!.compareTo(ranked[b]!) : result;
    });
    return ExpansionTile(
      key: ValueKey('$id-${task.running}-$urgent-$active'),
      tilePadding: EdgeInsets.zero,
      initiallyExpanded: urgent || active,
      title: UserPanelView(
          displayName: people[id]?.name ?? id,
          userId: id,
          detail: id,
          avatar: people[id]?.avatar,
          avatarColor: people[id]?.color,
          avatarSize: 20),
      subtitle: Text([
        batchInvitePersonSent(count),
        if (issues > 0) batchInviteNeedAttention(issues),
        if (active) batchInviteLabelSending,
      ].join(' · ')),
      children: [
        for (final item in items)
          ListTile(
            contentPadding: const EdgeInsets.only(left: 12),
            title: Text(item.operation == InviteOperation.history
                ? batchInviteHistoryShareRow(
                    policy.name(item.roomName, item.roomId))
                : policy.name(item.roomName, item.roomId)),
            subtitle: Text(
                '${stateLabel(item)}${item.reason == null ? '' : '\n${item.reason}'}'),
            leading: Icon(
                attention(item)
                    ? Icons.error_outline
                    : item.outcome == InviteOutcome.sent
                        ? Icons.check_circle_outline
                        : Icons.circle_outlined,
                color: attention(item)
                    ? Theme.of(context).colorScheme.error
                    : null),
          )
      ],
    );
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<void>(
        stream: task.statusChanged,
        builder: (context, _) {
          final policy = RedactionScope.of(context);
          final invitations = task.items.where(
            (i) => i.operation == InviteOperation.invite,
          );
          final sent =
              invitations.where((i) => i.outcome == InviteOutcome.sent).length;
          final skipped = invitations
              .where((i) => i.outcome == InviteOutcome.skipped)
              .length;
          final failures = invitations
              .where(
                (i) => {
                  InviteOutcome.failed,
                  InviteOutcome.blocked,
                  InviteOutcome.unconfirmed,
                }.contains(i.outcome),
              )
              .length;
          final remaining = task.count(InviteOutcome.canceled) +
              task.count(InviteOutcome.held);
          final unknown = task.count(InviteOutcome.unconfirmed) > 0;
          final media = MediaQuery.of(context).scale();
          final height = math.max(
            160.0,
            math.min(
              700.0,
              media.size.height - media.viewInsets.bottom - 80,
            ),
          );
          Widget button(String text, VoidCallback? tap,
                  {bool secondary = false}) =>
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: tap == null
                      ? ElevatedButton(
                          onPressed: null,
                          child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Text(text)))
                      : secondary
                          ? t.Button.secondary(text: text, onTap: tap)
                          : t.Button(text: text, onTap: tap),
                ),
              );
          return PopScope(
            canPop: !task.running,
            child: SizedBox(
              width: 560,
              height: height,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      task.running
                          ? batchInviteViewRunningTitle
                          : batchInviteViewDoneTitle,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      policy.name(
                        task.name,
                        task.items.firstOrNull?.roomId ?? task.name,
                      ),
                    ),
                    Semantics(
                      liveRegion: true,
                      child: Text([
                        batchInviteSummarySent(sent),
                        batchInviteSummarySkipped(skipped),
                        if (failures > 0) batchInviteNeedAttention(failures),
                        if (remaining > 0) batchInviteSummaryNotSent(remaining),
                      ].join(' · ')),
                    ),
                    if (task.running)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: LinearProgressIndicator(
                          value:
                              task.total == 0 ? 0 : task.current / task.total,
                        ),
                      ),
                    Expanded(
                        child: ListView(children: [
                      for (final id in recipientOrder()) recipient(context, id),
                      Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(batchInviteSentMeaning)),
                    ])),
                    if (task.running) ...[
                      button(
                        batchInviteContinueInBackground,
                        () => Navigator.pop(context),
                      ),
                      button(
                        task.stopping
                            ? batchInviteStoppingAfterThis
                            : batchInviteStopAfterThis,
                        task.stopping ? null : task.stop,
                        secondary: true,
                      ),
                      Text(batchInviteStopExplainer),
                    ] else ...[
                      if (task.canRetry)
                        button(
                          task.items.any(
                                  (i) => i.operation == InviteOperation.history)
                              ? batchInviteRetryFailedWithShares
                              : batchInviteRetryFailed(
                                  task.count(InviteOutcome.failed) +
                                      task.count(InviteOutcome.blocked)),
                          () => unawaited(task.retry()),
                        ),
                      if (task.canResume)
                        button(
                          batchInviteResume,
                          () => unawaited(task.resume()),
                          secondary: true,
                        ),
                      if (unknown) ...[
                        button(
                          batchInviteCheckUnconfirmed,
                          () => unawaited(task.reconcile()),
                          secondary: true,
                        ),
                        button(
                          batchInviteRetryUnconfirmedEllipsis,
                          () => unawaited(confirmUnknown(context)),
                          secondary: true,
                        ),
                      ],
                      button(batchInviteDone, () => Navigator.pop(context),
                          secondary: true),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      );
}
