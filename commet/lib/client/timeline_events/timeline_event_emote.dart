import 'package:commet/client/timeline.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';

abstract class TimelineEventEmote extends TimelineEvent {
  /// The emote's text as last edited, without the sender's name: what an
  /// edit starts from.
  String getPlaintextBody(Timeline timeline);
}
