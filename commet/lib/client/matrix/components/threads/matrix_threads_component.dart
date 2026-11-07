import 'dart:async';

import 'package:commet/client/attachment.dart';
import 'package:commet/client/components/component.dart';
import 'package:commet/client/components/threads/thread_component.dart';
import 'package:commet/client/components/threads/thread_preview_content.dart';
import 'package:commet/client/components/url_preview/outgoing_url_preview.dart';
import 'package:commet/client/matrix/components/threads/matrix_thread_timeline.dart';
import 'package:commet/client/matrix/components/threads/thread_follows.dart';
import 'package:commet/client/matrix/components/threads/thread_read_scope.dart';
import 'package:commet/client/matrix/components/threads/thread_reply_rules.dart';
import 'package:commet/client/matrix/components/threads/thread_reply_tracker.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/client/matrix/matrix_timeline.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event.dart';
import 'package:commet/client/room.dart';
import 'package:commet/client/timeline.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/debug/log.dart';
import 'package:flutter/foundation.dart';

import 'package:matrix/matrix.dart' as matrix;

class MatrixThreadsComponent
    implements ThreadsComponent<MatrixClient>, NeedsPostLoginInit {
  @override
  MatrixClient client;

  MatrixThreadsComponent(this.client);

  ThreadReplyTracker? _replyTracker;

  /// Vommet issues 785 and 1077: follows threads for you and keeps their
  /// thread reply rules.
  @override
  void postLoginInit() {
    if (_replyTracker != null) return;
    final tracker =
        _replyTracker = ThreadReplyTracker(client.getMatrixClient());
    client.getMatrixClient().onTimelineEvent.stream.listen(tracker.onEvent);
  }

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
      List<ProcessedAttachment>? processedAttachments,
      List<OutgoingUrlPreview>? urlPreviews}) async {
    if (room is! MatrixRoom) {
      return null;
    }

    var newMessage = await room.sendMessage(
        message: message,
        inReplyTo: inReplyTo,
        replaceEvent: replaceEvent,
        processedAttachments: processedAttachments,
        urlPreviews: urlPreviews,
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
      {bool followed = false, String? from, int limit = 25}) async {
    if (room is! MatrixRoom) return ThreadListPage([]);
    final mx = client.getMatrixClient();
    final mxRoom = room.matrixRoom;
    // Vommet issue 1077: "Following" = the threads you took part in, minus
    // the ones you unfollowed, plus the ones followed otherwise (by hand, a
    // mention, an older thread reply rule), fetched one by one.
    final response = await mx.getThreadRoots(room.identifier,
        include: followed ? matrix.Include.participated : null,
        limit: limit,
        from: from);
    final follows = followed ? ThreadFollows.of(mxRoom) : null;
    final raws = [
      for (final raw in response.chunk)
        if (follows?[raw.eventId]?.follow != false) raw,
    ];
    if (follows != null && from == null) {
      final listed = {for (final raw in raws) raw.eventId};
      // The most recently followed first: servers don't keep key order.
      final byTime = follows.entries.toList()
        ..sort((a, b) => b.value.ts.compareTo(a.value.ts));
      final extra = <String>{
        for (final MapEntry(:key, :value) in byTime)
          if (value.follow) key,
        for (final rootId in ThreadReplyRules.threadRootsIn(
            mx.globalPushRules, room.identifier))
          if (follows[rootId] == null) rootId,
      }.where((id) => !listed.contains(id)).take(_maxExtraFollowed);
      final fetched = await Future.wait(extra.map((id) async {
        try {
          return await mx.getOneRoomEvent(room.identifier, id);
        } catch (e, s) {
          Log.onError(e, s, content: "Could not fetch a followed thread");
          return null;
        }
      }));
      raws.addAll(fetched.nonNulls);
    }

    final threads = <ThreadSummary>[];
    for (final raw in raws) {
      final summary = await _summaryOf(mx, room, raw);
      if (summary != null) threads.add(summary);
    }
    if (follows != null && from == null) {
      threads.sort((a, b) => _activity(b).compareTo(_activity(a)));
    }
    return ThreadListPage(threads, nextBatch: response.nextBatch);
  }

  // Vommet: bounded New Home preview (Vommet issue 1144). Each fetch
  // method makes one discovery request. The caller owns the shared budget.
  Future<List<ThreadSummary>> previewParticipated(MatrixRoom room) async {
    final mx = client.getMatrixClient();
    final page = await mx.getThreadRoots(room.identifier,
        include: matrix.Include.participated, limit: 10);
    return [
      for (final raw in page.chunk.take(10))
        if (await _summaryOf(mx, room, raw,
                knownParticipated: true, preview: true)
            case final summary?)
          summary,
    ];
  }

  Iterable<({String rootId, int timestamp})> previewExtraRoots(
      MatrixRoom room) sync* {
    final entries = ThreadFollows.stored(room.matrixRoom);
    for (final entry in entries.entries) {
      if (entry.value.follow) {
        yield (rootId: entry.key, timestamp: entry.value.ts);
      }
    }
    final rules = client.getMatrixClient().globalPushRules;
    for (final rootId
        in ThreadReplyRules.threadRootsIn(rules, room.identifier)) {
      if (!entries.containsKey(rootId)) yield (rootId: rootId, timestamp: 0);
    }
  }

  Future<ThreadSummary?> previewRoot(MatrixRoom room, String rootId) async {
    final mx = client.getMatrixClient();
    final raw = await mx.getOneRoomEvent(room.identifier, rootId);
    return _summaryOf(mx, room, raw, preview: true);
  }

  /// Followed threads outside the server's list fetched for the first page.
  static const int _maxExtraFollowed = 50;

  static int _activity(ThreadSummary thread) =>
      (thread.latestReply ?? thread.root).originServerTs.millisecondsSinceEpoch;

  Future<ThreadSummary?> _summaryOf(
      matrix.Client mx, MatrixRoom room, matrix.MatrixEvent raw,
      {bool knownParticipated = false, bool preview = false}) async {
    Future<matrix.Event> resolve(matrix.Event event) async {
      if (!preview) return _decrypt(mx, event);
      if (event.type != matrix.EventTypes.Encrypted || event.redacted) {
        return event;
      }
      // A preview never asks other devices for encryption keys.
      return await mx.database.getEventById(event.eventId, room.matrixRoom) ??
          event;
    }

    final root =
        await resolve(matrix.Event.fromMatrixEvent(raw, room.matrixRoom));
    final info = threadAggregation(raw.unsigned);
    final replyCount = (info?["count"] as num?)?.toInt() ?? 0;
    // Vommet: a deleted root with no replies left is a deleted thread;
    // the server still lists it.
    if (root.redacted && replyCount == 0) return null;
    final latestJson = info?["latest_event"];
    matrix.Event? latest;
    if (latestJson is Map<String, dynamic>) {
      latest =
          await resolve(matrix.Event.fromJson(latestJson, room.matrixRoom));
    }
    final participated =
        knownParticipated || info?["current_user_participated"] == true;
    if (participated && !preview) {
      ThreadFollows.noteRepliedIn(room.matrixRoom, root.eventId);
    }
    return ThreadSummary(
      root: room.convertEvent(root),
      replyCount: replyCount,
      countReported: info?["count"] is num,
      latestReply: latest == null ? null : room.convertEvent(latest),
      participated: participated,
    );
  }

  @override
  bool isThreadFollowed(Room room, String rootId,
      {TimelineEvent? root, bool participated = false}) {
    if (room is! MatrixRoom) return false;
    ThreadFollows.watch(room.matrixRoom.client);
    return ThreadFollows.isFollowed(room.matrixRoom, rootId,
        root: root is MatrixTimelineEvent ? root.event : null,
        participated: participated);
  }

  @override
  Future<bool> loadThreadFollowed(Room room, String rootId) async {
    if (room is! MatrixRoom) return false;
    final mxRoom = room.matrixRoom;
    if (ThreadFollows.entryOf(mxRoom, rootId) != null) {
      return ThreadFollows.isFollowed(mxRoom, rootId);
    }
    // The server's copy: a stored root's thread summary (whether you took
    // part) is from when it arrived.
    matrix.Event? root;
    try {
      final raw = await mxRoom.client.getOneRoomEvent(mxRoom.id, rootId);
      root = matrix.Event.fromMatrixEvent(raw, mxRoom);
    } catch (e, s) {
      Log.onError(e, s, content: "Could not fetch a thread root");
      root = await mxRoom.getEventById(rootId).catchError((_) => null);
    }
    if (root != null && ThreadReadScopes.startedOrParticipated(root)) {
      // The menu and the lists only have the stored root; tell them.
      ThreadFollows.noteRepliedIn(mxRoom, rootId);
    }
    return ThreadFollows.isFollowed(mxRoom, rootId, root: root);
  }

  @override
  Future<void> setThreadFollowed(Room room, String rootId, bool follow) async {
    if (room is! MatrixRoom) return;
    await ThreadFollows.set(room.matrixRoom, rootId, follow);
  }

  @override
  Listenable get threadFollowsChanged => ThreadFollows.changed;

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
      countReported: info?["count"] is num,
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
      // Vommet issue 982: a cached first preview can be redacted too.
      _firstReplies.removeWhere((key, _) => key.startsWith("${event.roomId}|"));
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
    // Vommet issue 982: filter the bounded sample, never the server count or
    // event-based activity/read state. Conversion also applies blocking.
    final replies = <TimelineEvent>[];
    for (final raw in recent.chunk) {
      final event = room.convertEvent(await _decrypt(
          mx, matrix.Event.fromMatrixEvent(raw, room.matrixRoom)));
      if (isThreadReplyPreview(event)) replies.add(event);
    }
    final senders = replies.map((e) => e.senderId).toSet().take(3).toList();
    final latest = replies.firstOrNull;

    TimelineEvent? first;
    if (withFirstReply) {
      final firstKey = "${room.identifier}|$rootId";
      if (_firstReplies.containsKey(firstKey)) {
        first = _firstReplies[firstKey];
      } else {
        final page = await mx.getRelatingEventsWithRelType(
            room.identifier, rootId, matrix.RelationshipTypes.thread,
            limit: 1, dir: matrix.Direction.f);
        final raw = page.chunk.firstOrNull;
        if (raw != null) {
          final event = room.convertEvent(await _decrypt(
              mx, matrix.Event.fromMatrixEvent(raw, room.matrixRoom)));
          if (isThreadReplyPreview(event)) first = event;
        }
        _firstReplies[firstKey] = first;
      }
    }

    return ThreadPreviewExtras(
        firstReply: first,
        latestReply: latest,
        replyCount: count,
        recentSenderIds: senders,
        sampled: true,
        hasActivity:
            recent.chunk.any((e) => e.unsigned?["redacted_because"] == null));
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
