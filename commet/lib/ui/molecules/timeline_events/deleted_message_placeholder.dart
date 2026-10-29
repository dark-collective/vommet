// Vommet issue 306: a deleted (redacted) message leaves a muted one-line
// "Message deleted" in its place, like Element, instead of vanishing.
import 'package:commet/client/timeline.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/client/timeline_events/timeline_event_deleted.dart';
import 'package:commet/config/preferences/bool_preference.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// The experiment's switch: off hides deleted messages again. Kept here
/// instead of preferences.dart so this topic doesn't touch that busy file.
final experimentDeletedMessagePlaceholders = BoolPreference(
    "vommet_experiment_deleted_message_placeholders",
    defaultValue: true);

String get labelDeletedMessagePlaceholder => Intl.message("Message deleted",
    name: "labelDeletedMessagePlaceholder",
    desc: "Shown in the timeline where a message was deleted");

String labelDeletedMessagePlaceholderBy(String name) => Intl.message(
    "Message deleted by $name",
    args: [name],
    name: "labelDeletedMessagePlaceholderBy",
    desc:
        "Shown in the timeline where someone other than the sender (e.g. a moderator) deleted a message");

String labelDeletedMessagePlaceholderReason(String text, String reason) =>
    Intl.message("$text (reason: $reason)",
        args: [text, reason],
        name: "labelDeletedMessagePlaceholderReason",
        desc:
            "Adds the reason given for deleting a message to its timeline placeholder; text is 'Message deleted' or 'Message deleted by ...'");

/// Whether [event] shows as a "Message deleted" row in [timeline].
bool showsDeletedPlaceholder(Timeline timeline, TimelineEvent event) =>
    experimentDeletedMessagePlaceholders.value &&
    timeline.deletedMessageInfo(event) != null;

/// The placeholder's text. Names who deleted it only when that wasn't the
/// sender; [nameOf] turns a user ID into a display name.
String deletedMessageText(DeletedMessageInfo info,
    {required String senderId, required String Function(String) nameOf}) {
  final by = info.deletedBy;
  var text = by == null || by == senderId
      ? labelDeletedMessagePlaceholder
      : labelDeletedMessagePlaceholderBy(nameOf(by));

  final reason = info.reason;
  if (reason != null) {
    text = labelDeletedMessagePlaceholderReason(text, reason);
  }
  return text;
}

/// The muted body of a deleted message's row.
class DeletedMessagePlaceholder extends StatelessWidget {
  const DeletedMessagePlaceholder({required this.text, super.key});

  final String text;

  static DeletedMessagePlaceholder? forEvent(
      Timeline timeline, TimelineEvent event,
      {Key? key}) {
    final info = timeline.deletedMessageInfo(event);
    if (info == null) return null;
    return DeletedMessagePlaceholder(
      key: key,
      text: deletedMessageText(info,
          senderId: event.senderId,
          nameOf: (id) => timeline.room.getMemberOrFallback(id).displayName),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      children: [
        Icon(Icons.delete_outline, size: 16, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: color,
                  fontStyle: FontStyle.italic,
                ),
          ),
        ),
      ],
    );
  }
}
