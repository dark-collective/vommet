import 'dart:convert';

import 'package:commet/client/matrix/components/threads/matrix_thread_timeline.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_timeline.dart';
import 'package:commet/client/timeline.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:matrix/matrix.dart' as matrix;

abstract class MatrixTimelineEvent implements TimelineEvent {
  final MatrixClient client;

  matrix.Event event;

  MatrixTimelineEvent(this.event, {required this.client});

  @override
  bool get editable => false;

  @override
  String get eventId => event.eventId;

  @override
  DateTime get originServerTs => event.originServerTs;

  @override
  String get senderId => event.senderId;

  @override
  String get source =>
      const JsonEncoder.withIndent('  ').convert(event.toJson());

  @override
  bool get mentionsRoom => event.mentions.room;

  @override
  List<String> get mentions => event.mentions.userIds;

  @override
  TimelineEventStatus get status => switch (event.status) {
        matrix.EventStatus.error => TimelineEventStatus.error,
        matrix.EventStatus.sending => TimelineEventStatus.sending,
        matrix.EventStatus.sent => TimelineEventStatus.sent,
        matrix.EventStatus.synced => TimelineEventStatus.synced,
      };

  @override
  String get plainTextBody => event.plaintextBody;

  /// The event as last edited by its sender (its `m.new_content`), or the
  /// event itself when it has no edits or no timeline is given.
  matrix.Event getDisplayEvent(Timeline? tl) {
    var mx = getTimeline(tl);

    if (mx == null) return event;

    return event.getDisplayEvent(mx);
  }

  matrix.Timeline? getTimeline(Timeline? tl) {
    if (tl == null) return null;

    if (tl is MatrixThreadTimeline) {
      return tl.mainRoomTimeline.matrixTimeline;
    } else {
      return (tl as MatrixTimeline).matrixTimeline;
    }
  }
}
