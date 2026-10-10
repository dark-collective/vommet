import 'package:commet/client/attachment.dart';
import 'package:commet/client/components/threads/thread_component.dart';
import 'package:commet/client/matrix/components/threads/matrix_thread_timeline.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/client/matrix/matrix_timeline.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event.dart';
import 'package:commet/client/room.dart';
import 'package:commet/client/timeline.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';

import 'package:matrix/matrix.dart' as matrix;

class MatrixThreadsComponent implements ThreadsComponent<MatrixClient> {
  @override
  MatrixClient client;

  MatrixThreadsComponent(this.client);

  @override
  bool isEventInResponseToThread(TimelineEvent event, Timeline timeline) {
    if (event is! MatrixTimelineEvent) {
      return false;
    }

    var mxEvent = event.event;
    var relation = mxEvent.content["m.relates_to"];
    if (relation == null) {
      return false;
    }

    if (relation is! Map<String, dynamic>) {
      return false;
    }

    if (relation["rel_type"] == matrix.RelationshipTypes.thread) {
      return true;
    }

    if (relation.containsKey("m.in_reply_to")) {
      var replyingEventID = relation["m.in_reply_to"]["event_id"];
      var replyingEvent = timeline.tryGetEvent(replyingEventID);
      if (replyingEvent != null) {
        return isEventInResponseToThread(replyingEvent, timeline);
      }
    }

    return false;
  }

  @override
  bool isHeadOfThread(TimelineEvent event, Timeline timeline) {
    matrix.Timeline? tl;

    if (timeline is MatrixTimeline) {
      tl = timeline.matrixTimeline;
    }

    if (timeline is MatrixThreadTimeline) {
      if (event.eventId == timeline.threadRootId) {
        return true;
      }
      tl = timeline.mainRoomTimeline.matrixTimeline;
    }

    if (tl == null) {
      return false;
    }

    if (event is! MatrixTimelineEvent) {
      return false;
    }

    if (event.event.unsigned?.containsKey("m.relations") == true) {
      var relations =
          event.event.unsigned!["m.relations"] as Map<String, dynamic>;
      if (relations.containsKey("m.thread")) {
        return true;
      }
    }

    return event.event.hasAggregatedEvents(tl, matrix.RelationshipTypes.thread);
  }

  @override
  TimelineEvent? getFirstReplyToThread(TimelineEvent event, Timeline timeline) {
    matrix.Timeline? tl;

    if (timeline is MatrixTimeline) {
      tl = timeline.matrixTimeline;
    }

    if (timeline is MatrixThreadTimeline) {
      tl = timeline.mainRoomTimeline.matrixTimeline;
    }

    if (tl == null) {
      return null;
    }

    if (event is! MatrixTimelineEvent) {
      return null;
    }

    if (event.event.unsigned?.containsKey("m.relations") == true) {
      var relations =
          event.event.unsigned!["m.relations"] as Map<String, dynamic>;
      if (relations.containsKey("m.thread")) {
        var info = relations["m.thread"] as Map<String, dynamic>;
        if (info.containsKey("latest_event") == true) {
          var matrixEvent =
              matrix.Event.fromJson(info["latest_event"], tl.room);

          tl.addAggregatedEvent(matrixEvent);

          return (timeline.room as MatrixRoom).convertEvent(matrixEvent);
        }
      }
    }

    var events =
        event.event.aggregatedEvents(tl, matrix.RelationshipTypes.thread);

    var firstEvent = events.firstOrNull;
    if (firstEvent == null) {
      return null;
    }
    return (timeline.room as MatrixRoom).convertEvent(firstEvent);
  }

  @override
  Future<Timeline?> getThreadTimeline(
      {required Timeline roomTimeline,
      required String threadRootEventId}) async {
    if (roomTimeline is! MatrixTimeline) {
      return null;
    }

    var client = roomTimeline.client as MatrixClient;
    var room = (roomTimeline.room as MatrixRoom);

    var timeline = MatrixThreadTimeline(
        client: client,
        room: room,
        threadRootId: threadRootEventId,
        mainRoomTimeline: roomTimeline,
        component: this);

    await timeline.loadMoreHistory();

    return timeline;
  }

  @override
  Future<TimelineEvent?> sendMessage(
      {required String threadRootEventId,
      required Room room,
      String? message,
      TimelineEvent? inReplyTo,
      TimelineEvent? replaceEvent,
      List<ProcessedAttachment>? processedAttachments}) async {
    if (room is! MatrixRoom) {
      return null;
    }

    var newMessage = await room.sendMessage(
        message: message,
        inReplyTo: inReplyTo,
        replaceEvent: replaceEvent,
        processedAttachments: processedAttachments,
        threadRootEventId: threadRootEventId) as MatrixTimelineEvent?;

    if (room.timeline != null) {
      var index = room.timeline!.events
          .indexWhere((element) => element.eventId == threadRootEventId);

      (room.timeline as MatrixTimeline)
          .matrixTimeline!
          .addAggregatedEvent(newMessage!.event);

      if (index != -1) {
        room.timeline!.notifyChanged(index);
      }
    }

    return null;
  }

  @override
  Future<ThreadListPage> listThreads(Room room,
      {bool participated = false, String? from, int limit = 25}) async {
    if (room is! MatrixRoom) return ThreadListPage([]);
    final mx = client.getMatrixClient();
    final response = await mx.getThreadRoots(room.identifier,
        include: participated ? matrix.Include.participated : null,
        limit: limit,
        from: from);

    final threads = <ThreadSummary>[];
    for (final raw in response.chunk) {
      final root = await _decrypt(
          mx, matrix.Event.fromMatrixEvent(raw, room.matrixRoom));
      final info = threadAggregation(raw.unsigned);
      final latestJson = info?["latest_event"];
      matrix.Event? latest;
      if (latestJson is Map<String, dynamic>) {
        latest = await _decrypt(
            mx, matrix.Event.fromJson(latestJson, room.matrixRoom));
      }
      threads.add(ThreadSummary(
        root: room.convertEvent(root),
        replyCount: (info?["count"] as num?)?.toInt() ?? 0,
        latestReply: latest == null ? null : room.convertEvent(latest),
        participated: info?["current_user_participated"] == true,
      ));
    }
    return ThreadListPage(threads, nextBatch: response.nextBatch);
  }

  Future<matrix.Event> _decrypt(matrix.Client mx, matrix.Event event) async {
    if (event.type != matrix.EventTypes.Encrypted) return event;
    final encryption = mx.encryption;
    if (encryption == null) return event;
    try {
      return await encryption.decryptRoomEvent(event);
    } catch (_) {
      return event;
    }
  }

  /// The bundled `m.thread` aggregation in an event's `unsigned`, if any.
  static Map<String, dynamic>? threadAggregation(
      Map<String, dynamic>? unsigned) {
    final relations = unsigned?["m.relations"];
    if (relations is! Map) return null;
    final thread = relations[matrix.RelationshipTypes.thread];
    return thread is Map<String, dynamic> ? thread : null;
  }

  @override
  bool isThreadUnread(Room room, ThreadSummary thread) {
    if (room is! MatrixRoom) return false;
    final latest = thread.latestReply;
    if (latest == null) return false;
    final receipts = room.matrixRoom.receiptState;
    return threadHasUnread(
      ownUserId: client.self?.identifier,
      latestSenderId: latest.senderId,
      latestTs: latest.originServerTs.millisecondsSinceEpoch,
      receiptTimestamps: [
        receipts.global.latestOwnReceipt?.ts,
        receipts.byThread[thread.rootId]?.latestOwnReceipt?.ts,
      ],
    );
  }

  /// A thread has unread replies when its newest reply is someone else's and
  /// came after every receipt of yours that covers it: your receipt in the
  /// thread, or an unthreaded one (which marks everything before it read).
  static bool threadHasUnread({
    required String? ownUserId,
    required String latestSenderId,
    required int latestTs,
    required List<int?> receiptTimestamps,
  }) {
    if (latestSenderId == ownUserId) return false;
    final readUpTo = receiptTimestamps
        .whereType<int>()
        .fold<int>(0, (newest, ts) => ts > newest ? ts : newest);
    return latestTs > readUpTo;
  }
}
