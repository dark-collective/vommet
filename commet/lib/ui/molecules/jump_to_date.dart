import 'package:commet/client/client.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet (chat navigation): pick a day and jump to the room's first message
/// from then on (MSC3030 /timestamp_to_event). Opened from a date divider,
/// the room menu and in-chat search.
class JumpToDate {
  static String get promptJumpToDate => Intl.message("Jump to date…",
      desc: "Menu option that opens a calendar to jump to a day in the chat",
      name: "promptJumpToDate");

  static String get labelJumpToDateTitle => Intl.message("Jump to date",
      desc: "Title of the calendar for jumping to a day in the chat",
      name: "labelJumpToDateTitle");

  static String get promptJumpToDateGo => Intl.message("Jump",
      desc: "Button in the jump-to-date calendar that jumps to the picked day",
      name: "promptJumpToDateGo");

  static String get labelJumpToDateYesterday => Intl.message("Yesterday",
      desc: "Shortcut in the jump-to-date calendar",
      name: "labelJumpToDateYesterday");

  static String get labelJumpToDateLastWeek => Intl.message("Last week",
      desc: "Shortcut in the jump-to-date calendar: seven days ago",
      name: "labelJumpToDateLastWeek");

  static String get labelJumpToDateFirstMessage => Intl.message("First message",
      desc: "Shortcut in the jump-to-date calendar: the start of the room",
      name: "labelJumpToDateFirstMessage");

  static String get labelJumpToDateUnsupported => Intl.message(
      "This server can't jump to dates",
      desc:
          "Shown when the user's homeserver doesn't support jumping to a date",
      name: "labelJumpToDateUnsupported");

  static String get labelJumpToDateNothing =>
      Intl.message("No messages from that day on",
          desc: "Shown when jumping to a date found no messages after it",
          name: "labelJumpToDateNothing");

  static String get labelJumpToDateFailed =>
      Intl.message("Couldn't jump to that date",
          desc: "Shown when jumping to a date failed",
          name: "labelJumpToDateFailed");

  /// The start of the room, for "First message".
  static final roomStart = DateTime.fromMillisecondsSinceEpoch(0);

  static Future<void> open(BuildContext context, Room room,
      {DateTime? initial}) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final picked = await AdaptiveDialog.show<DateTime>(context,
        title: labelJumpToDateTitle,
        scrollable: true,
        builder: (context) => _JumpToDatePicker(initial: initial));
    if (picked == null) return;

    String message;
    try {
      final eventId = await room.eventIdAtTime(picked);
      if (eventId != null) {
        EventBus.jumpToEvent.add(eventId);
        return;
      }
      message = labelJumpToDateNothing;
    } on JumpToDateUnsupported {
      message = labelJumpToDateUnsupported;
    } catch (e, s) {
      Log.onError(e, s, content: "Jump to date failed");
      message = labelJumpToDateFailed;
    }
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }
}

class _JumpToDatePicker extends StatefulWidget {
  const _JumpToDatePicker({this.initial});
  final DateTime? initial;

  @override
  State<_JumpToDatePicker> createState() => _JumpToDatePickerState();
}

class _JumpToDatePickerState extends State<_JumpToDatePicker> {
  late final DateTime today = DateUtils.dateOnly(DateTime.now());
  late DateTime day = DateUtils.dateOnly(widget.initial ?? DateTime.now());

  void jump(DateTime value) => Navigator.of(context).pop(value);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 340,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            ActionChip(
                label: Text(JumpToDate.labelJumpToDateYesterday),
                onPressed: () => jump(today.subtract(const Duration(days: 1)))),
            ActionChip(
                label: Text(JumpToDate.labelJumpToDateLastWeek),
                onPressed: () => jump(today.subtract(const Duration(days: 7)))),
            ActionChip(
                label: Text(JumpToDate.labelJumpToDateFirstMessage),
                onPressed: () => jump(JumpToDate.roomStart)),
          ]),
          CalendarDatePicker(
            initialDate: day.isAfter(today) ? today : day,
            firstDate: DateTime(2014),
            lastDate: today,
            onDateChanged: (value) => setState(() => day = value),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: tiamat.Button(
              text: JumpToDate.promptJumpToDateGo,
              onTap: () => jump(day),
            ),
          ),
        ],
      ),
    );
  }
}
