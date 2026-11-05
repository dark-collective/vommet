import 'package:commet/client/timeline.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:flutter/widgets.dart';

abstract class TimelineEventEmote extends TimelineEvent {
  /// The emote's text as last edited, without the sender's name: what an
  /// edit starts from.
  String getPlaintextBody(Timeline timeline);

  /// Vommet issue 325: the emote with the sender's name, drawn like a
  /// message's text (formatting, links, mentions, emoji).
  Widget buildFormattedContent({Timeline? timeline});
}
