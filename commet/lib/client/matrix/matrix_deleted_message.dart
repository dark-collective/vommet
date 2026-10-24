import 'package:commet/client/timeline_events/timeline_event_deleted.dart';
import 'package:matrix/matrix.dart' as matrix;

/// Vommet issue 306: event types that showed as a message before they were
/// deleted. Deleted reactions, state events and the like stay hidden.
const _messageTypes = {
  matrix.EventTypes.Message,
  matrix.EventTypes.Sticker,
  matrix.EventTypes.Encrypted,
  "org.matrix.msc3381.poll.start",
  "m.poll.start",
};

/// The placeholder details for [event] if it is a deleted message, otherwise
/// null.
///
/// Deleting strips an edit's or thread reply's relation, so one loaded
/// already deleted can't be told apart from a deleted message.
DeletedMessageInfo? matrixDeletedMessageInfo(matrix.Event event) {
  if (!event.redacted) return null;
  if (event.stateKey != null) return null;
  if (!_messageTypes.contains(event.type)) return null;

  final redaction = event.redactedBecause;
  final reason = redaction?.content["reason"];
  return DeletedMessageInfo(
    deletedBy: redaction?.senderId,
    reason: reason is String && reason.trim().isNotEmpty ? reason.trim() : null,
  );
}
