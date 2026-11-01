import 'package:commet/client/client.dart';
import 'package:commet/client/components/scheduled_messages/scheduled_messages.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/utils/clock_format.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet: strings and dialogs of scheduled send (MSC4140 delayed events).
class ScheduleStrings {
  static String get scheduleMessageLabel => Intl.message(
        "Schedule message",
        name: "scheduleMessageLabel",
        desc: "Composer menu item that sends the typed message at a later time",
      );

  static String get scheduleUnsupportedTooltip => Intl.message(
        "Your homeserver can't hold messages for later",
        name: "scheduleUnsupportedTooltip",
        desc: "Under the grayed-out Schedule message item when the homeserver "
            "has no delayed events",
      );

  static String get scheduleUnsupportedTitle => Intl.message(
        "Scheduling isn't available",
        name: "scheduleUnsupportedTitle",
        desc: "Title of the dialog explaining why Schedule message is "
            "grayed out",
      );

  static String get scheduleUnsupportedExplanation => Intl.message(
        "Scheduled messages wait on your homeserver, so they go out even when "
        "Vommet is closed. Your homeserver doesn't support this yet (it needs "
        "delayed events, MSC4140). The option turns on by itself once it does.",
        name: "scheduleUnsupportedExplanation",
        desc: "Explains why Schedule message is grayed out",
      );

  static String get scheduleNotHereExplanation => Intl.message(
        "Only a new text message can be scheduled: not an edit, a message with "
        "files or a forward, or a command.",
        name: "scheduleNotHereExplanation",
        desc: "Explains why Schedule message can't schedule what is in the "
            "message box",
      );

  static String get schedulePickTitle => Intl.message(
        "Send at",
        name: "schedulePickTitle",
        desc: "Title of the dialog that picks when a scheduled message is sent",
      );

  static String get schedulePickCustom => Intl.message(
        "Pick a date and time",
        name: "schedulePickCustom",
        desc: "Scheduled send: opens a date and a time picker",
      );

  static String get scheduleInOneHour => Intl.message(
        "In 1 hour",
        name: "scheduleInOneHour",
        desc: "Scheduled send: preset one hour from now",
      );

  static String get scheduleToday => Intl.message(
        "Today",
        name: "scheduleToday",
        desc: "Scheduled send: the day part of a time later today",
      );

  static String get scheduleTomorrow => Intl.message(
        "Tomorrow",
        name: "scheduleTomorrow",
        desc: "Scheduled send: the day part of a time tomorrow",
      );

  static String get schedulePrivacyNote => Intl.message(
        "Your homeserver holds the message until then. In an encrypted room it "
        "is encrypted now, so people who join the room before it is sent can't "
        "read it.",
        name: "schedulePrivacyNote",
        desc: "Note in the scheduled send picker about how the message waits",
      );

  static String scheduledFor(String when) => Intl.message(
        "Scheduled for $when",
        args: [when],
        name: "scheduledFor",
        desc: "Confirmation after scheduling a message; when is like 'Tomorrow "
            "09:00'",
      );

  static String scheduledCount(int count) => Intl.plural(
        count,
        one: "1 scheduled message",
        other: "$count scheduled messages",
        args: [count],
        name: "scheduledCount",
        desc: "Bar above the message box: how many messages wait to be sent "
            "in this room",
      );

  static String get scheduledView => Intl.message(
        "View",
        name: "scheduledView",
        desc: "Button on the scheduled messages bar that opens the list",
      );

  static String get scheduledListTitle => Intl.message(
        "Scheduled messages",
        name: "scheduledListTitle",
        desc: "Title of the list of messages waiting to be sent in a room",
      );

  static String get scheduledNone => Intl.message(
        "No scheduled messages in this room.",
        name: "scheduledNone",
        desc: "Shown in the scheduled messages list when it is empty",
      );

  static String get scheduledEncryptedText => Intl.message(
        "Encrypted message (can't be shown on this device)",
        name: "scheduledEncryptedText",
        desc: "Scheduled messages list: the text of an encrypted message "
            "this device can't decrypt",
      );

  static String get scheduledSendNow => Intl.message(
        "Send now",
        name: "scheduledSendNow",
        desc: "Scheduled messages list: sends the message right away",
      );

  static String get scheduledEdit => Intl.message(
        "Edit",
        name: "scheduledEdit",
        desc: "Scheduled messages list: puts the text back in the message box "
            "and unschedules it",
      );

  static String get scheduledChangeTime => Intl.message(
        "Change time",
        name: "scheduledChangeTime",
        desc: "Scheduled messages list: picks a new time for the message",
      );

  static String get scheduledDelete => Intl.message(
        "Delete",
        name: "scheduledDelete",
        desc: "Scheduled messages list: unschedules the message, it is never "
            "sent",
      );

  static String get scheduledDeleteConfirm => Intl.message(
        "Delete this scheduled message? It won't be sent.",
        name: "scheduledDeleteConfirm",
        desc: "Confirmation before deleting a scheduled message",
      );

  static String get scheduleFailedTitle => Intl.message(
        "Not scheduled",
        name: "scheduleFailedTitle",
        desc: "Title of the error shown when scheduling a message failed",
      );

  static String scheduleDays(int days) => Intl.plural(
        days,
        one: "1 day",
        other: "$days days",
        args: [days],
        name: "scheduleDays",
        desc: "Scheduled send: a number of days",
      );

  static String scheduleHours(int hours) => Intl.plural(
        hours,
        one: "1 hour",
        other: "$hours hours",
        args: [hours],
        name: "scheduleHours",
        desc: "Scheduled send: a number of hours",
      );

  static String scheduleMaxDelay(String duration) => Intl.message(
        "The longest it can wait is $duration.",
        args: [duration],
        name: "scheduleMaxDelay",
        desc: "Scheduled send: added to the error when the time is too far "
            "ahead; duration is like '7 days' or '12 hours'",
      );
}

/// Vommet: picks when a scheduled message goes out.
class SchedulePicker {
  /// "Today 18:00", "Tomorrow 09:00" or "Mon, Oct 27 09:00".
  static String whenLabel(BuildContext context, DateTime t, {DateTime? now}) {
    now ??= DateTime.now();
    final local = t.toLocal();
    final time = ClockFormat.timeOf(context, local);
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    final days = day.difference(today).inDays;
    if (days == 0) return "${ScheduleStrings.scheduleToday} $time";
    if (days == 1) return "${ScheduleStrings.scheduleTomorrow} $time";
    final date = local.year == now.year
        ? DateFormat.MMMEd().format(local)
        : DateFormat.yMMMEd().format(local);
    return "$date $time";
  }

  static String durationLabel(Duration d) => d.inDays >= 1
      ? ScheduleStrings.scheduleDays(d.inDays)
      : ScheduleStrings.scheduleHours(d.inHours < 1 ? 1 : d.inHours);

  static Future<DateTime?> show(BuildContext context, {DateTime? initial}) {
    final now = DateTime.now();
    final presets = ScheduledMessages.presets(now);
    return AdaptiveDialog.show<DateTime>(
      context,
      title: ScheduleStrings.schedulePickTitle,
      builder: (dialogContext) => SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, t) in presets.indexed)
              SizedBox(
                height: 50,
                child: tiamat.TextButton(
                  i == 0 && t.difference(now).inMinutes <= 61
                      ? "${ScheduleStrings.scheduleInOneHour} · ${ClockFormat.timeOf(dialogContext, t)}"
                      : whenLabel(dialogContext, t, now: now),
                  key: ValueKey("schedule-preset-$i"),
                  icon: Icons.schedule,
                  onTap: () => Navigator.of(dialogContext).pop(t),
                ),
              ),
            SizedBox(
              height: 50,
              child: tiamat.TextButton(
                ScheduleStrings.schedulePickCustom,
                key: const ValueKey("schedule-preset-custom"),
                icon: Icons.edit_calendar_outlined,
                onTap: () async {
                  final t = await pickCustom(
                    dialogContext,
                    initial: initial ?? presets.first,
                  );
                  if (t != null && dialogContext.mounted) {
                    Navigator.of(dialogContext).pop(t);
                  }
                },
              ),
            ),
            const SizedBox(height: 8),
            privacyNote(dialogContext),
          ],
        ),
      ),
    );
  }

  static Widget privacyNote(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline,
              size: 14,
              color: Theme.of(context).colorScheme.secondary,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: tiamat.Text.labelLow(ScheduleStrings.schedulePrivacyNote),
            ),
          ],
        ),
      );

  static Future<DateTime?> pickCustom(
    BuildContext context, {
    required DateTime initial,
  }) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !context.mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  /// Explains why Schedule message is grayed out.
  static Future<void> explainUnsupported(BuildContext context) =>
      AdaptiveDialog.show(
        context,
        title: ScheduleStrings.scheduleUnsupportedTitle,
        builder: (context) => SizedBox(
          width: 400,
          child: tiamat.Text.body(
            ScheduleStrings.scheduleUnsupportedExplanation,
          ),
        ),
      );

  /// Explains why what is in the message box can't be scheduled.
  static Future<void> explainNotHere(BuildContext context) =>
      AdaptiveDialog.show(
        context,
        title: ScheduleStrings.scheduleUnsupportedTitle,
        builder: (context) => SizedBox(
          width: 400,
          child: tiamat.Text.body(ScheduleStrings.scheduleNotHereExplanation),
        ),
      );

  static Future<void> showError(BuildContext context, Object error) {
    var text = "$error";
    if (error is ScheduleException && error.maxDelay != null) {
      text =
          "$text ${ScheduleStrings.scheduleMaxDelay(durationLabel(error.maxDelay!))}";
    }
    return AdaptiveDialog.show(
      context,
      title: ScheduleStrings.scheduleFailedTitle,
      builder: (context) => SizedBox(width: 400, child: tiamat.Text.body(text)),
    );
  }
}

/// Vommet: "2 scheduled messages · View" above the message box of [room].
class ScheduledMessagesBar extends StatefulWidget {
  const ScheduledMessagesBar({
    required this.room,
    required this.onEdit,
    super.key,
  });
  final Room room;

  /// Puts a scheduled message's text back in the message box.
  final void Function(String text) onEdit;

  @override
  State<ScheduledMessagesBar> createState() => _ScheduledMessagesBarState();
}

class _ScheduledMessagesBarState extends State<ScheduledMessagesBar> {
  @override
  void initState() {
    super.initState();
    ScheduledMessages.changed.addListener(update);
    ScheduledMessages.refresh(widget.room.client).catchError((
      Object error,
      StackTrace trace,
    ) {
      Log.onError(error, trace, content: "Could not load scheduled messages");
      return const <ScheduledMessage>[];
    });
  }

  @override
  void dispose() {
    ScheduledMessages.changed.removeListener(update);
    super.dispose();
  }

  void update() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final items = ScheduledMessages.inRoom(
      widget.room.client,
      widget.room.identifier,
    );
    if (items.isEmpty) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
      child: Material(
        key: const ValueKey("scheduled-messages-bar"),
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(5),
        child: InkWell(
          borderRadius: BorderRadius.circular(5),
          onTap: () => ScheduledMessagesList.show(
            context,
            widget.room,
            onEdit: widget.onEdit,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
            child: Row(
              children: [
                Icon(
                  Icons.schedule_send_outlined,
                  size: 16,
                  color: colors.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: tiamat.Text.label(
                    "${ScheduleStrings.scheduledCount(items.length)} · ${SchedulePicker.whenLabel(context, items.first.sendAt)}",
                  ),
                ),
                tiamat.Text.labelEmphasised(
                  ScheduleStrings.scheduledView,
                  color: colors.primary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Vommet: the messages waiting to be sent in [room]: Send now, Edit, Change
/// time, Delete.
class ScheduledMessagesList extends StatefulWidget {
  const ScheduledMessagesList({
    required this.room,
    required this.onEdit,
    super.key,
  });
  final Room room;
  final void Function(String text) onEdit;

  static Future<void> show(
    BuildContext context,
    Room room, {
    required void Function(String text) onEdit,
  }) =>
      AdaptiveDialog.show(
        context,
        title: ScheduleStrings.scheduledListTitle,
        scrollable: false,
        initialHeightMobile: 0.6,
        builder: (context) => ScheduledMessagesList(room: room, onEdit: onEdit),
      );

  @override
  State<ScheduledMessagesList> createState() => _ScheduledMessagesListState();
}

class _ScheduledMessagesListState extends State<ScheduledMessagesList> {
  final Map<String, Future<String?>> texts = {};
  bool busy = false;

  Client get client => widget.room.client;

  @override
  void initState() {
    super.initState();
    ScheduledMessages.changed.addListener(update);
  }

  @override
  void dispose() {
    ScheduledMessages.changed.removeListener(update);
    super.dispose();
  }

  void update() {
    if (mounted) setState(() {});
  }

  Future<String?> textOf(ScheduledMessage m) =>
      texts.putIfAbsent(m.delayId, () => ScheduledMessages.textOf(client, m));

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
    } catch (error, trace) {
      Log.onError(error, trace, content: "Scheduled message action failed");
      if (mounted) await SchedulePicker.showError(context, error);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = ScheduledMessages.inRoom(client, widget.room.identifier);
    final height = MediaQuery.of(context).size.height;
    return SizedBox(
      width: 480,
      height: height * 0.5,
      child: items.isEmpty
          ? Center(child: tiamat.Text.labelLow(ScheduleStrings.scheduledNone))
          : ListView(
              padding: EdgeInsets.zero,
              children: [for (final m in items) entry(m)],
            ),
    );
  }

  Widget entry(ScheduledMessage m) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      key: ValueKey("scheduled-${m.delayId}"),
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.schedule, size: 14, color: colors.primary),
              const SizedBox(width: 6),
              tiamat.Text.label(SchedulePicker.whenLabel(context, m.sendAt)),
            ],
          ),
          const SizedBox(height: 4),
          FutureBuilder<String?>(
            future: textOf(m),
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const SizedBox(height: 18);
              }
              final text = snapshot.data;
              return text == null
                  ? tiamat.Text.labelLow(ScheduleStrings.scheduledEncryptedText)
                  : tiamat.Text.body(
                      text,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    );
            },
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            children: [
              TextButton.icon(
                key: ValueKey("scheduled-send-now-${m.delayId}"),
                icon: const Icon(Icons.send, size: 16),
                label: Text(ScheduleStrings.scheduledSendNow),
                onPressed: busy
                    ? null
                    : () => run(
                          () => ScheduledMessages.sendNow(client, m.delayId),
                        ),
              ),
              FutureBuilder<String?>(
                future: textOf(m),
                builder: (context, snapshot) => TextButton.icon(
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: Text(ScheduleStrings.scheduledEdit),
                  onPressed: busy || snapshot.data == null
                      ? null
                      : () => run(() async {
                            await ScheduledMessages.cancel(client, m.delayId);
                            widget.onEdit(snapshot.data!);
                            if (mounted) Navigator.of(context).maybePop();
                          }),
                ),
              ),
              TextButton.icon(
                icon: const Icon(Icons.more_time, size: 16),
                label: Text(ScheduleStrings.scheduledChangeTime),
                onPressed: busy
                    ? null
                    : () => run(() async {
                          final t = await SchedulePicker.show(
                            context,
                            initial: m.sendAt,
                          );
                          if (t == null) return;
                          await ScheduledMessages.reschedule(client, m, t);
                        }),
              ),
              TextButton.icon(
                icon: Icon(Icons.delete_outline, size: 16, color: colors.error),
                label: Text(
                  ScheduleStrings.scheduledDelete,
                  style: TextStyle(color: colors.error),
                ),
                onPressed: busy
                    ? null
                    : () => run(() async {
                          final ok = await AdaptiveDialog.confirmation(
                            context,
                            title: ScheduleStrings.scheduledDelete,
                            prompt: ScheduleStrings.scheduledDeleteConfirm,
                            confirmationText: ScheduleStrings.scheduledDelete,
                            cancelText: MaterialLocalizations.of(
                              context,
                            ).cancelButtonLabel,
                            dangerous: true,
                          );
                          if (ok != true) return;
                          await ScheduledMessages.cancel(client, m.delayId);
                        }),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
