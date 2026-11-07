import 'package:commet/client/matrix/timeline_events/matrix_timeline_event.dart';
import 'package:commet/client/timeline_events/timeline_event_unknown.dart';
import 'package:intl/intl.dart';

class MatrixTimelineEventUnknown extends MatrixTimelineEvent
    implements TimelineEventUnknown {
  MatrixTimelineEventUnknown(super.event, {required super.client});

  String get labelMessageDeleted => Intl.message("Message deleted",
      name: "labelMessageDeleted",
      desc: "Room list preview text when the last message was deleted");

  // Vommet issue 982: unknown is not evidence of deletion.
  String get labelUnsupportedEvent => Intl.message("Unsupported event",
      name: "labelUnsupportedEvent",
      desc: "Preview of an event this client cannot render; not a redaction");

  // Vommet: a deleted (redacted) message becomes an unknown event; the room
  // list showed it as "Unknown Event Type: m.room.message".
  @override
  String get plainTextBody =>
      event.redacted ? labelMessageDeleted : labelUnsupportedEvent;
}
