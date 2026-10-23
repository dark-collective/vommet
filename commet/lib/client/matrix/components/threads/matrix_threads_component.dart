import 'dart:async';

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
    // Vommet: Tuwunel hands out a next_batch even on the last page, and the
    // root only comes with the (empty) page after it; without these extra
    // rounds a short thread opened without its root until scrolled up.
    for (var i = 0;
        i < 3 && !timeline.finished && timeline.events.length < 20;
        i++) {
      await timeline.loadMoreHistory();
    }

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
      final replyCount = (info?["count"] as num?)?.toInt() ?? 0;
      // Vommet: a deleted root with no replies left is a deleted thread;
      // the server still lists it.
      if (root.redacted && replyCount == 0) continue;
      final latestJson = info?["latest_event"];
      matrix.Event? latest;
      if (latestJson is Map<String, dynamic>) {
        latest = await _decrypt(
            mx, matrix.Event.fromJson(latestJson, room.matrixRoom));
      }
      threads.add(ThreadSummary(
        root: room.convertEvent(root),
        replyCount: replyCount,
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

  @override
  ThreadSummary? getThreadSummary(TimelineEvent root, Timeline timeline) {
    matrix.Timeline? tl;
    if (timeline is MatrixTimeline) tl = timeline.matrixTimeline;
    if (timeline is MatrixThreadTimeline) {
      tl = timeline.mainRoomTimeline.matrixTimeline;
    }
    if (tl == null || root is! MatrixTimelineEvent) return null;
    final room = timeline.room;
    if (room is! MatrixRoom) return null;

    final info = threadAggregation(root.event.unsigned);
    final bundledCount = (info?["count"] as num?)?.toInt() ?? 0;
    matrix.Event? latest;
    final latestJson = info?["latest_event"];
    if (latestJson is Map<String, dynamic>) {
      latest = matrix.Event.fromJson(latestJson, tl.room);
    }

    // Replies seen live since the root was fetched; the bundled count
    // already covers anything up to the bundled latest reply.
    final bundledId = latest?.eventId;
    final bundledTs = latest?.originServerTs;
    var newer = 0;
    for (final e
        in root.event.aggregatedEvents(tl, matrix.RelationshipTypes.thread)) {
      if (e.eventId == bundledId) continue;
      if (bundledTs != null && !e.originServerTs.isAfter(bundledTs)) continue;
      newer++;
      if (latest == null || e.originServerTs.isAfter(latest.originServerTs)) {
        latest = e;
      }
    }

    final count = bundledCount + newer;
    if (latest == null && count == 0) return null;
    return ThreadSummary(
      root: root,
      replyCount: count,
      latestReply: latest == null ? null : room.convertEvent(latest),
      participated: info?["current_user_participated"] == true,
    );
  }

  final Map<String, Future<ThreadPreviewExtras>> _extras = {};
  final Map<String, TimelineEvent?> _firstReplies = {};

  final StreamController<String> _threadsChanged = StreamController.broadcast();
  StreamSubscription? _redactionSub;

  @override
  Stream<String> get onThreadsChanged {
    // A deleted reply doesn't change its root, so cards can't tell; any
    // deletion in a room reloads that room's previews.
    _redactionSub ??=
        client.getMatrixClient().onTimelineEvent.stream.listen((event) {
      if (event.type != matrix.EventTypes.Redaction) return;
      _extras.removeWhere((key, _) => key.startsWith("${event.roomId}|"));
      _threadsChanged.add(event.roomId ?? "");
    });
    return _threadsChanged.stream;
  }

  @override
  Future<ThreadPreviewExtras> loadThreadPreviewExtras(
      Room room, ThreadSummary thread,
      {bool withFirstReply = false}) {
    if (room is! MatrixRoom) return Future.value(ThreadPreviewExtras());
    final key = "${room.identifier}|${thread.rootId}|"
        "${thread.latestReply?.eventId}|${thread.replyCount}|$withFirstReply";
    final cached = _extras[key];
    if (cached != null) return cached;
    // A long session sees many threads; the cache only saves requests.
    if (_extras.length > 500) _extras.clear();
    if (_firstReplies.length > 2000) _firstReplies.clear();
    final future = _loadExtras(room, thread.rootId, withFirstReply);
    _extras[key] = future;
    future.catchError((_) {
      _extras.remove(key);
      return ThreadPreviewExtras();
    });
    return future;
  }

  Future<ThreadPreviewExtras> _loadExtras(
      MatrixRoom room, String rootId, bool withFirstReply) async {
    final mx = client.getMatrixClient();
    // The root as the server has it now: the copy stored with the room
    // keeps the reply count it had when it was fetched.
    final freshRoot = mx
        .getOneRoomEvent(room.identifier, rootId)
        .then<matrix.MatrixEvent?>((e) => e)
        .catchError((_) => null);
    final recent = await mx.getRelatingEventsWithRelType(
        room.identifier, rootId, matrix.RelationshipTypes.thread,
        limit: 20, dir: matrix.Direction.b);
    final root = await freshRoot;
    final count =
        (threadAggregation(root?.unsigned)?["count"] as num?)?.toInt();
    // A server may still list a deleted reply.
    final replies = recent.chunk
        .where((e) => e.unsigned?["redacted_because"] == null)
        .toList();

    final senders = <String>[];
    for (final e in replies) {
      if (!senders.contains(e.senderId)) senders.add(e.senderId);
      if (senders.length == 3) break;
    }

    TimelineEvent? latest;
    final newest = replies.firstOrNull;
    if (newest != null) {
      latest = room.convertEvent(await _decrypt(
          mx, matrix.Event.fromMatrixEvent(newest, room.matrixRoom)));
    }

    TimelineEvent? first;
    if (withFirstReply) {
      if (_firstReplies.containsKey(rootId)) {
        first = _firstReplies[rootId];
      } else {
        final page = await mx.getRelatingEventsWithRelType(
            room.identifier, rootId, matrix.RelationshipTypes.thread,
            limit: 1, dir: matrix.Direction.f);
        final raw = page.chunk.firstOrNull;
        if (raw != null) {
          first = room.convertEvent(await _decrypt(
              mx, matrix.Event.fromMatrixEvent(raw, room.matrixRoom)));
        }
        _firstReplies[rootId] = first;
      }
    }

    return ThreadPreviewExtras(
        firstReply: first,
        latestReply: latest,
        replyCount: root == null ? null : (count ?? 0),
        recentSenderIds: senders);
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
