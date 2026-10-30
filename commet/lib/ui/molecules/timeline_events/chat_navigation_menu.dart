import 'package:commet/client/client.dart';
import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/client/components/read_receipts/read_receipt_component.dart';
import 'package:commet/client/timeline.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/client/timeline_events/timeline_event_message.dart';
import 'package:commet/ui/molecules/edit_history_dialog.dart';
import 'package:commet/ui/molecules/timeline_events/timeline_event_menu.dart';
import 'package:commet/utils/clock_format.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Vommet (chat navigation): the message menu's "Read at" line in direct
/// messages and its "Edit history" entry.
class ChatNavigationMenu {
  static String labelReadAt(String when) => Intl.message("Read $when",
      args: [when],
      desc:
          "First line of the menu on your own message in a direct message: when the other person read it, e.g. 'today at 14:32'",
      name: "labelReadAt",
      examples: const {"when": "today at 14:32"});

  static String labelReadBy(String when) => Intl.message("Read by $when",
      args: [when],
      desc:
          "First line of the menu on your own message in a direct message, when the other person has read a later message: they had read this one by then, e.g. 'today at 14:32'",
      name: "labelReadBy",
      examples: const {"when": "today at 14:32"});

  static String labelWhenToday(String time) => Intl.message("today at $time",
      args: [time],
      desc: "A time today, used inside 'Read …', e.g. 'today at 14:32'",
      name: "labelWhenToday",
      examples: const {"time": "14:32"});

  static String labelWhenYesterday(String time) =>
      Intl.message("yesterday at $time",
          args: [time],
          desc: "A time yesterday, used inside 'Read …'",
          name: "labelWhenYesterday",
          examples: const {"time": "14:32"});

  static String labelWhenOnDate(String date, String time) =>
      Intl.message("$date at $time",
          args: [date, time],
          desc: "A date and time, used inside 'Read …', e.g. 'Oct 12 at 14:32'",
          name: "labelWhenOnDate",
          examples: const {"date": "Oct 12", "time": "14:32"});

  /// "today at 14:32", "yesterday at 9:05 PM", "Oct 12 at 14:32".
  static String when(BuildContext context, DateTime time, {DateTime? now}) {
    final local = time.toLocal();
    final today = now ?? DateTime.now();
    final clock = ClockFormat.timeOf(context, local);
    final days = DateTime(today.year, today.month, today.day)
        .difference(DateTime(local.year, local.month, local.day))
        .inDays;
    if (days == 0) return labelWhenToday(clock);
    if (days == 1) return labelWhenYesterday(clock);
    final date = local.year == today.year
        ? DateFormat.MMMd().format(local)
        : DateFormat.yMMMd().format(local);
    return labelWhenOnDate(date, clock);
  }

  /// Whether the other person read [event] (null: not known to be read), and
  /// whether their receipt is on a later message.
  static ({DateTime time, bool later})? readState(
      Timeline timeline, TimelineEvent event) {
    final room = timeline.room;
    final me = room.client.self?.identifier;
    if (me == null || event.senderId != me) return null;
    final dms = room.client.getComponent<DirectMessagesComponent>();
    if (dms == null || !dms.isRoomDirectMessage(room)) return null;
    final partner = dms.getDirectMessagePartnerId(room);
    if (partner == null) return null;
    final receipt =
        room.getComponent<ReadReceiptComponent>()?.latestReceiptOf(partner);
    if (receipt == null) return null;

    // Newest first: a receipt at a smaller index is on a later message.
    final events = timeline.events;
    final at = events.indexWhere((e) => e.eventId == event.eventId);
    final read = events.indexWhere((e) => e.eventId == receipt.eventId);
    if (at == -1 || read == -1 || read > at) return null;
    return (time: receipt.time, later: read < at);
  }

  static TimelineEventMenuEntry? readAtEntry(BuildContext context,
      Timeline timeline, TimelineEvent event, Function()? onActionFinished) {
    final state = readState(timeline, event);
    if (state == null) return null;
    final whenText = when(context, state.time);
    return TimelineEventMenuEntry(
      name: state.later ? labelReadBy(whenText) : labelReadAt(whenText),
      icon: Icons.done_all,
      action: (_) => onActionFinished?.call(),
    );
  }

  static TimelineEventMenuEntry? editHistoryEntry(
      Timeline timeline, TimelineEvent event, Function()? onActionFinished) {
    if (event is! TimelineEventMessage || !event.isEdited(timeline)) {
      return null;
    }
    return TimelineEventMenuEntry(
      name: EditHistoryDialog.promptEditHistory,
      icon: Icons.history_edu,
      action: (context) {
        onActionFinished?.call();
        EditHistoryDialog.show(context, event: event, timeline: timeline);
      },
    );
  }
}
