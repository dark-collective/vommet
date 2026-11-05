import 'dart:math';

import 'package:commet/client/matrix/timeline_events/matrix_timeline_event.dart';
import 'package:commet/client/timeline.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';

/// Vommet issue 699: the files and the text of one send are separate events,
/// so Vommet tags them with one shared id under [key]; one Delete then
/// removes them together. Other clients ignore the key.
class SendBatch {
  static const String key = "im.vommet.send_batch";

  static String newId() {
    final random = Random.secure();
    return List.generate(16, (_) => random.nextInt(36).toRadixString(36))
        .join();
  }

  /// The send id [event] carries, if any.
  static String? of(TimelineEvent event) {
    if (event is! MatrixTimelineEvent) return null;
    final id = event.event.content[key];
    return id is String && id.isNotEmpty ? id : null;
  }

  /// The events in [timeline] that [event]'s sender sent together with it,
  /// [event] included; empty when it carries no send id.
  static List<TimelineEvent> together(TimelineEvent event, Timeline timeline) {
    final id = of(event);
    if (id == null) return const [];
    return [
      for (final e in timeline.events)
        if (e.senderId == event.senderId && of(e) == id) e
    ];
  }
}
