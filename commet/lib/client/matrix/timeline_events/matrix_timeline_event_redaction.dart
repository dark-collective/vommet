import 'package:commet/client/matrix/timeline_events/matrix_timeline_event.dart';
import 'package:commet/client/timeline_events/timeline_event_redaction.dart';
import 'package:intl/intl.dart';

class MatrixTimelineEventRedaction extends MatrixTimelineEvent
    implements TimelineEventRedaction {
  MatrixTimelineEventRedaction(super.event, {required super.client});

  String get labelRedactionEvent => Intl.message("Deleted a message",
      name: "labelRedactionEvent",
      desc: "Text for a message deletion (redaction) event");

  // Vommet: a deletion has no body, so it read as the SDK's "Unknown message
  // format of type m.room.redaction" wherever it showed as text.
  @override
  String get plainTextBody => labelRedactionEvent;
}
