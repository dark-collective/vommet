import 'package:commet/client/matrix/timeline_events/matrix_timeline_event.dart';
import 'package:commet/client/timeline_events/timeline_event_poll_relation.dart';
import 'package:intl/intl.dart';

/// Vommet issue 494: a poll vote or end, in the unstable (MSC3381) or stable
/// form. Without its own type it was an unknown event, drawn as "Unknown
/// Event Type: org.matrix.msc3381.poll.response" whenever it showed as a row.
class MatrixTimelineEventPollRelation extends MatrixTimelineEvent
    implements TimelineEventPollRelation {
  MatrixTimelineEventPollRelation(super.event, {required super.client});

  static const responseTypes = {
    "org.matrix.msc3381.poll.response",
    "m.poll.response",
  };

  static const endTypes = {
    "org.matrix.msc3381.poll.end",
    "m.poll.end",
  };

  static bool isPollRelationType(String type) =>
      responseTypes.contains(type) || endTypes.contains(type);

  String get labelPollVoteEvent => Intl.message("Voted in a poll",
      name: "labelPollVoteEvent",
      desc: "Text for a vote in a poll, where it shows as its own row");

  String get labelPollEndEvent => Intl.message("Ended a poll",
      name: "labelPollEndEvent",
      desc: "Text for the end of a poll, where it shows as its own row");

  @override
  String get plainTextBody =>
      endTypes.contains(event.type) ? labelPollEndEvent : labelPollVoteEvent;
}
