import 'package:commet/client/matrix/components/threads/thread_reply_rules.dart';
import 'package:commet/client/matrix/components/threads/thread_reply_tracker.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/pages/room_info/room_info_rows.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet issue 785: "Thread replies notify me" in Settings › Notifications
/// and room info.

String threadReplyNotifyLabel(ThreadReplyNotify choice) => switch (choice) {
      ThreadReplyNotify.all => "All threads",
      ThreadReplyNotify.mine => "Only threads I'm in",
    };

const String threadReplyNotifyTitle = "Thread replies notify me";

const String threadReplyNotifyExplain =
    "With \"Only threads I'm in\", replies in other threads don't notify. "
    "Mentions, keywords, the main timeline and new threads still do. You're "
    "in a thread once you reply or are mentioned in it, or if you started "
    "it. Rooms with their own notification level keep it.";

/// The choice made in the list: [choice] null is "Use default (…)".
class ThreadReplyNotifyPick {
  const ThreadReplyNotifyPick(this.choice);
  final ThreadReplyNotify? choice;
}

/// The room's "Thread replies notify me" row; a tap picks its own choice or
/// "Use default".
class ThreadReplyNotifyRow extends StatefulWidget {
  const ThreadReplyNotifyRow(this.room, {super.key});
  final matrix.Room room;

  @override
  State<ThreadReplyNotifyRow> createState() => _ThreadReplyNotifyRowState();
}

class _ThreadReplyNotifyRowState extends State<ThreadReplyNotifyRow> {
  // The rules change on the next sync; show the pick until then.
  ThreadReplyNotifyPick? _picked;

  matrix.PushRuleSet? get _rules => widget.room.client.globalPushRules;

  Future<void> _pick() async {
    final room = widget.room;
    final own = _picked != null
        ? _picked!.choice
        : ThreadReplyRules.roomChoice(_rules, room.id);
    final defaultChoice = ThreadReplyRules.accountChoice(_rules);
    final pick = await AdaptiveDialog.show<ThreadReplyNotifyPick>(context,
        title: threadReplyNotifyTitle, builder: (context) {
      Widget choice(ThreadReplyNotify? value, String text) {
        final selected = value == own;
        return ListTile(
          key: ValueKey("thread-reply-notify-${value?.name ?? "default"}"),
          leading: Icon(selected
              ? Icons.radio_button_checked
              : Icons.radio_button_unchecked),
          title: Text(text),
          selected: selected,
          onTap: () => Navigator.of(context).pop(ThreadReplyNotifyPick(value)),
        );
      }

      return Column(mainAxisSize: MainAxisSize.min, children: [
        choice(null, "Use default (${threadReplyNotifyLabel(defaultChoice)})"),
        for (final value in ThreadReplyNotify.values)
          choice(value, threadReplyNotifyLabel(value)),
      ]);
    });
    if (pick == null) return;
    try {
      await ThreadReplyRules.setRoomChoice(_rules, room.id, pick.choice,
          put: ThreadReplyTracker.putOn(room.client),
          delete: ThreadReplyTracker.deleteOn(room.client));
      if (mounted) setState(() => _picked = pick);
    } catch (e, s) {
      Log.onError(e, s, content: "Couldn't save thread reply notifications");
    }
  }

  @override
  Widget build(BuildContext context) {
    final rules = _rules;
    final own = _picked != null
        ? _picked!.choice
        : ThreadReplyRules.roomChoice(rules, widget.room.id);
    return InfoRow(
      key: const ValueKey("room-info-thread-reply-notify"),
      icon: Icons.notifications_paused_outlined,
      title: threadReplyNotifyTitle,
      value: own == null
          ? "Default (${threadReplyNotifyLabel(ThreadReplyRules.accountChoice(rules))})"
          : threadReplyNotifyLabel(own),
      onTap: _pick,
    );
  }
}

/// Settings › Notifications › Threads: the account's choice, set on every
/// Matrix account at once.
class ThreadReplyNotifySettings extends StatefulWidget {
  const ThreadReplyNotifySettings({super.key});

  @override
  State<ThreadReplyNotifySettings> createState() =>
      _ThreadReplyNotifySettingsState();
}

class _ThreadReplyNotifySettingsState extends State<ThreadReplyNotifySettings> {
  ThreadReplyNotify? _picked;

  List<matrix.Client> get clients => [
        for (final c in clientManager?.clients ?? [])
          if (c is MatrixClient) c.getMatrixClient(),
      ];

  Future<void> _set(ThreadReplyNotify choice) async {
    setState(() => _picked = choice);
    for (final c in clients) {
      try {
        await ThreadReplyRules.setAccountChoice(c.globalPushRules, choice,
            put: ThreadReplyTracker.putOn(c),
            delete: ThreadReplyTracker.deleteOn(c));
      } catch (e, s) {
        Log.onError(e, s, content: "Couldn't save thread reply notifications");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = clients;
    if (list.isEmpty) return const SizedBox.shrink();
    final current =
        _picked ?? ThreadReplyRules.accountChoice(list.first.globalPushRules);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: tiamat.Text.labelLow(threadReplyNotifyExplain),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<ThreadReplyNotify>(
              key: const ValueKey("thread-reply-notify-default"),
              showSelectedIcon: false,
              segments: [
                for (final value in ThreadReplyNotify.values)
                  ButtonSegment(
                      value: value, label: Text(threadReplyNotifyLabel(value))),
              ],
              selected: {current},
              onSelectionChanged: (s) => _set(s.first),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: tiamat.Text.labelLow(
              "Rooms can override this in their info page."),
        ),
      ],
    );
  }
}
