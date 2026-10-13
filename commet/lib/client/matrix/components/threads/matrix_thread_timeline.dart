import 'dart:async';

import 'package:collection/collection.dart';
import 'package:commet/client/client.dart';
import 'package:commet/client/components/threads/thread_component.dart';
import 'package:commet/client/matrix/components/read_receipts/matrix_read_receipt_component.dart';
import 'package:commet/client/matrix/components/threads/thread_receipts.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/client/matrix/matrix_timeline.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';

import 'package:matrix/matrix.dart' as matrix;

class MatrixThreadTimeline implements Timeline {
  @override
  Client client;

  @override
  late List<TimelineEvent> events;

  @override
  Room room;

  MatrixTimeline mainRoomTimeline;

  ThreadsComponent component;

  String threadRootId;

  @override
  StreamController<int> onChange = StreamController.broadcast();

  @override
  StreamController<int> onEventAdded = StreamController.broadcast();

  @override
  StreamController<int> onRemove = StreamController.broadcast();

  final StreamController<void> _loadingStatusChangedController =
      StreamController.broadcast();

  @override
  Stream<void> get onLoadingStatusChanged =>
      _loadingStatusChangedController.stream;

  late List<StreamSubscription> subs;

  String? nextBatch;
  bool finished = false;

  Future? nextChunkRequest;

  @override
  bool get canLoadFuture => false;

  @override
  bool get canLoadHistory => nextBatch != null && nextChunkRequest != null;

  @override
  bool get isLoadingFuture => false;

  @override
  bool isLoadingHistory = false;

  MatrixThreadTimeline({
    required this.client,
    required this.room,
    required this.threadRootId,
    required this.mainRoomTimeline,
    required this.component,
    this.nextBatch,
  }) {
    subs = [
      mainRoomTimeline.onEventAdded.stream.listen(onMainTimelineEventAdded),
      mainRoomTimeline.onChange.stream.listen(onMainTimelineEventChanged),
      mainRoomTimeline.onRemove.stream.listen(onMainTimelineEventRemoved),
    ];

    events = List.empty(growable: true);
  }

  Future<List<TimelineEvent>> getThreadEvents(
      {int limit = 20, String? nextBatch}) async {
    var client = this.client as MatrixClient;
    var room = this.room as MatrixRoom;

    var mx = client.getMatrixClient();
    var data = await mx.request(matrix.RequestType.GET,
        "/client/unstable/rooms/${room.identifier}/relations/$threadRootId/m.thread",
        query: {
          "limit": limit.toString(),
          // Vommet: ask for newest first explicitly; the code below relies on it.
          "dir": "b",
          if (nextBatch != null) "from": nextBatch
        });

    var chunk = List<Map<String, dynamic>>.from(data["chunk"] as Iterable);

    var mxevents =
        chunk.map((e) => matrix.Event.fromJson(e, room.matrixRoom)).toList();

    for (var i = 0; i < mxevents.length; i++) {
      var event = mxevents[i];

      if (event.type == "m.room.encrypted") {
        var decrypted = await mx.encryption?.decryptRoomEvent(event);
        if (decrypted != null) {
          mxevents[i] = decrypted;
        }
      }
    }

    for (var event in mxevents) {
      mainRoomTimeline.matrixTimeline?.addAggregatedEvent(event);
    }

    var convertedEvents = mxevents
        .map((e) =>
            room.convertEvent(e, timeline: mainRoomTimeline.matrixTimeline))
        .toList();

    this.nextBatch = data["next_batch"] as String?;

    if (this.nextBatch == null) {
      finished = true;
      var root = data["original_event"] as Map<String, dynamic>?;
      // Vommet: original_event is a Synapse extension; other servers (e.g.
      // Tuwunel) leave it out, and a thread opened from the thread list
      // would then have no root message.
      if (root == null) {
        try {
          root = await mx
              .getOneRoomEvent(room.identifier, threadRootId)
              .then((e) => e.toJson());
        } catch (_) {}
      }
      if (root != null) {
        var matrixEvent = matrix.Event.fromJson(root, room.matrixRoom);
        if (matrixEvent.type == "m.room.encrypted") {
          var decrypted = await mx.encryption?.decryptRoomEvent(matrixEvent);
          if (decrypted != null) {
            matrixEvent = decrypted;
          }
        }
        var event = room.convertEvent(matrixEvent);
        convertedEvents.add(event);
      }
    }

    return convertedEvents;
  }

  @override
  bool canDeleteEvent(TimelineEvent event) {
    return mainRoomTimeline.canDeleteEvent(event);
  }

  // Vommet: decryption diagnostics are counted on the room's own timeline.
  @override
  void endVisit() {}

  @override
  Future<void> close() async {
    for (var sub in subs) {
      sub.cancel();
    }
  }

  @override
  Future<void> deleteEvent(TimelineEvent event) {
    return mainRoomTimeline.deleteEvent(event);
  }

  @override
  Future<TimelineEvent?> fetchEventById(String eventId) {
    return mainRoomTimeline.fetchEventById(eventId);
  }

  @override
  Future<TimelineEvent?> fetchEventByIdInternal(String eventId) {
    return mainRoomTimeline.fetchEventByIdInternal(eventId);
  }

  @override
  bool hasEvent(String eventId) {
    return events.any((element) => element.eventId == eventId);
  }

  @override
  void insertEvent(int index, TimelineEvent event) {}

  @override
  Future<void> loadMoreHistory() async {
    if (finished) {
      return;
    }

    if (nextChunkRequest != null) {
      return;
    }

    isLoadingHistory = true;

    nextChunkRequest = getThreadEvents(nextBatch: nextBatch);
    var nextEvents = await nextChunkRequest;

    nextChunkRequest = null;

    // Vommet: the view expects newest first. Keep the page in that order
    // whatever order the server sent, and don't add an event twice (a reply
    // that arrived by sync while the page loaded is already listed).
    final page = List<TimelineEvent>.from(nextEvents as List)
      ..removeWhere((e) => hasEvent(e.eventId));
    mergeSort(page,
        compare: (a, b) => b.originServerTs.compareTo(a.originServerTs));
    for (var event in page) {
      events.add(event);
      onEventAdded.add(events.length - 1);
    }

    isLoadingHistory = false;
  }

  @override
  Future<void> loadMoreFuture() {
    throw UnimplementedError();
  }

  @override
  void markAsRead(TimelineEvent event) {
    // Vommet: read state per thread (experiment).
    if (!ThreadReceipts.enabled) return;
    if (event.status != TimelineEventStatus.synced &&
        event.status != TimelineEventStatus.sent) {
      return;
    }
    final room = this.room as MatrixRoom;
    final receipts = room.getComponent<MatrixReadReceiptComponent>();
    ThreadReceipts.markThreadRead(room.matrixRoom, threadRootId, event.eventId,
        public: receipts?.usePublicReadReceiptsForRoom ??
            room.matrixRoom.client.receiptsPublicByDefault);
  }

  @override
  void notifyChanged(int index) {}

  @override
  TimelineEvent? tryGetEvent(String eventId) {
    return mainRoomTimeline.tryGetEvent(eventId);
  }

  bool isEventInThisThread(TimelineEvent event) {
    if (event is! MatrixTimelineEvent) {
      return false;
    }

    if (event.eventId == threadRootId) {
      return true;
    }

    var mxEvent = event.event;
    var relation = mxEvent.content["m.relates_to"];
    if (relation == null) {
      return false;
    }

    if (relation is! Map<String, dynamic>) {
      return false;
    }

    if (relation["rel_type"] != matrix.RelationshipTypes.thread) {
      return false;
    }

    if (relation["event_id"] == threadRootId) {
      return true;
    }

    var reply = relation["m.in_reply_to"] as Map<String, dynamic>?;

    if (reply == null) {
      return false;
    }

    var replyingEventID = reply["event_id"];

    if (replyingEventID == threadRootId) {
      return true;
    }

    var replyingEvent = mainRoomTimeline.tryGetEvent(replyingEventID);
    if (replyingEvent != null) {
      return isEventInThisThread(replyingEvent as MatrixTimelineEvent);
    }

    return false;
  }

  void onMainTimelineEventAdded(int index) {
    var event = mainRoomTimeline.events[index];

    if (!isEventInThisThread(event)) {
      return;
    }

    // Vommet: the room timeline re-announces thread events this view already
    // loaded (it pages through the same messages), which listed them twice.
    // An event already here is refreshed in place; a new one goes where its
    // time puts it, since the room timeline's order knows nothing of the
    // thread's own pages or its root.
    final existing = indexOfEvent(event);
    if (existing != -1) {
      events[existing] = event;
      onChange.add(existing);
      return;
    }

    final at = insertIndexNewestFirst(
        events.map((e) => e.originServerTs).toList(), event.originServerTs);
    events.insert(at, event);
    onEventAdded.add(at);
  }

  /// Where an event at [ts] goes in [newestFirst]: before the first one that
  /// isn't newer, so a tie counts as the newer arrival.
  static int insertIndexNewestFirst(List<DateTime> newestFirst, DateTime ts) {
    final i = newestFirst.indexWhere((t) => !t.isAfter(ts));
    return i == -1 ? newestFirst.length : i;
  }

  /// This view's copy of [event]: same id, or the local echo it replaced
  /// (a sent message keeps its transaction id until the server's copy
  /// arrives).
  int indexOfEvent(TimelineEvent event) {
    final index = events.indexWhere((e) => e.eventId == event.eventId);
    if (index != -1 || event is! MatrixTimelineEvent) return index;
    final txnId = event.event.transactionId;
    if (txnId == null) return -1;
    return events.indexWhere((e) => e.eventId == txnId);
  }

  void onMainTimelineEventChanged(int index) {
    var event = mainRoomTimeline.events[index];
    if (isEventInThisThread(event)) {
      var index = indexOfEvent(event);

      // Vommet: an event this thread hasn't listed yet (typically the root,
      // which the main timeline re-announces whenever a reply is aggregated
      // onto it) used to overwrite the newest reply at index 0.
      if (index == -1) return;

      events[index] = event;
      onChange.add(index);
    }
  }

  void onMainTimelineEventRemoved(int index) {
    var event = mainRoomTimeline.events[index];
    if (isEventInThisThread(event)) {
      var index =
          events.indexWhere((element) => element.eventId == event.eventId);

      if (index != -1) {
        events.removeAt(index);
        onRemove.add(index);
      }
    }
  }

  @override
  bool isEventRedacted(TimelineEvent<Client> event) {
    var e = event as MatrixTimelineEvent;
    return e.event.getDisplayEvent(mainRoomTimeline.matrixTimeline!).redacted;
  }

  @override
  String getDisplayId(TimelineEvent<Client> event) {
    var e = event as MatrixTimelineEvent;
    var ev = e.event.getDisplayEvent(mainRoomTimeline.matrixTimeline!);

    return "thread-${threadRootId}-${event.eventId}-${ev.eventId}";
  }
}
