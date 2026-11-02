import 'package:commet/client/matrix/timeline_events/matrix_timeline_event.dart';
import 'package:commet/client/timeline_events/timeline_event_add_reaction.dart';
import 'package:intl/intl.dart';

class MatrixTimelineEventAddReaction extends MatrixTimelineEvent
    implements TimelineEventAddReaction {
  MatrixTimelineEventAddReaction(super.event, {required super.client});

  String labelReactionEvent(String key) => Intl.message("Reacted $key",
      args: [key],
      name: "labelReactionEvent",
      desc: "Text for a reaction event, shown as its own row");

  // Vommet: a reaction has no body, so it read as the SDK's "Unknown message
  // format of type m.reaction" wherever it showed as text.
  @override
  String get plainTextBody {
    final relation = event.content["m.relates_to"];
    final key = relation is Map ? relation["key"] : null;
    return labelReactionEvent(key is String ? key : "");
  }

  @override
  String? get reactedToEventId => event.relationshipEventId;
}
