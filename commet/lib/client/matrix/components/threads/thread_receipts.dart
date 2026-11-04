import 'package:commet/utils/vommet_unread.dart';
import 'package:collection/collection.dart';
import 'package:commet/client/matrix/components/threads/thread_follows.dart';
import 'package:commet/client/matrix/components/threads/thread_read_scope.dart';
import 'package:commet/client/matrix/components/threads/thread_reply_rules.dart';
import 'package:commet/debug/log.dart';
import 'package:matrix/matrix.dart' as matrix;

/// Vommet: threaded read receipts (MSC3771), for "Read state per thread"
/// (see [ThreadReadScopes]).
///
/// With it on for a room, reading a thread sends a receipt for that thread,
/// and reading the room's main timeline sends a receipt for `main` instead
/// of an unthreaded one, so opening the room no longer marks every thread
/// read. Marking the whole room read (room list menu) stays unthreaded.
class ThreadReceipts {
  static bool enabledFor(matrix.Room room) =>
      ThreadReadScopes.scopeFor(room) != ThreadReadScope.off;

  /// The last receipt sent per room and thread, so scrolling doesn't resend.
  static final _sent = Expando<Map<String, String>>();

  static bool isThreadReply(matrix.Event event) =>
      event.relationshipType == matrix.RelationshipTypes.thread;

  /// Marks the main timeline read up to its newest synced event that isn't
  /// a thread reply.
  static Future<void> markMainRead(matrix.Timeline timeline,
      {required bool public}) async {
    final event = newestMainEvent(timeline);
    if (event == null) return;
    final room = timeline.room;
    // Vommet issue 843: other people's threads get new replies while the
    // main timeline stays the same, so they're read even when the main
    // receipt is already sent (each thread skips its own resends).
    if (!_alreadySent(room, "main", event.eventId)) {
      try {
        await room.client.setReadMarker(room.id, mFullyRead: event.eventId);
      } catch (_) {
        // The marker request precedes the receipt request. A failed marker
        // must not leave the dedupe cache claiming the receipt was sent.
        _forgetSent(room, "main", event.eventId);
        rethrow;
      }
      await _post(room, event.eventId, "main", public: public);
    }
    if (ThreadReadScopes.scopeFor(room) == ThreadReadScope.mine) {
      await _readOtherThreads(timeline, public: public);
    }
  }

  /// Vommet issues 805 and 1077: with "Threads I follow", reading the room
  /// also reads the threads you don't follow, up to their newest reply the
  /// main timeline has, as if per-thread read state were off for them.
  static Future<void> _readOtherThreads(matrix.Timeline timeline,
      {required bool public}) async {
    final room = timeline.room;
    final me = room.client.userID;
    final newest = <String, matrix.Event>{};
    final roots = <String, matrix.Event>{};
    final mine = <String>{};
    // Newest first, so the first reply seen per thread is its newest.
    for (final e in timeline.events) {
      if (!e.status.isSynced) continue;
      final rootId = isThreadReply(e) ? e.relationshipEventId : null;
      if (rootId != null) {
        if (e.senderId == me) mine.add(rootId);
        newest.putIfAbsent(rootId, () => e);
      } else {
        roots[e.eventId] = e;
      }
    }
    final follows = ThreadFollows.stored(room);
    for (final MapEntry(key: rootId, value: reply) in newest.entries) {
      // A follow or unfollow wins; else threads you started, replied or
      // were mentioned in are followed.
      final entry = follows[rootId];
      if (entry != null && entry.follow) continue;
      if (entry == null) {
        if (mine.contains(rootId)) continue;
        if (ThreadReplyRules.hasThread(room.client.globalPushRules, rootId)) {
          continue;
        }
      }
      if (readByOwnReceipts(room, reply)) continue;
      if (entry == null && await _participated(room, rootId, roots[rootId])) {
        continue;
      }
      if (_alreadySent(room, rootId, reply.eventId)) continue;
      await _post(room, reply.eventId, rootId, public: public);
    }
  }

  /// Whether thread [rootId] is one you started or took part in; the root
  /// is fetched when the main timeline doesn't have it.
  static Future<bool> _participated(
      matrix.Room room, String rootId, matrix.Event? root) async {
    final known = _participation[room]?[rootId];
    if (known != null) return known;
    try {
      root ??= await room.getEventById(rootId);
    } catch (e, s) {
      Log.onError(e, s, content: "Could not fetch a thread root");
    }
    // An unknown root is treated as yours, so its thread is never marked
    // read by mistake.
    final result = root == null || ThreadReadScopes.startedOrParticipated(root);
    (_participation[room] ??= {})[rootId] = result;
    return result;
  }

  static final _participation = Expando<Map<String, bool>>();

  /// Marks thread [rootId] read up to [eventId]. [mainTimeline] is the
  /// room's main timeline, for [_refreshMainRead].
  static Future<void> markThreadRead(
      matrix.Room room, String rootId, String eventId,
      {required bool public, matrix.Timeline? mainTimeline}) async {
    if (eventId == rootId) return;
    if (_alreadySent(room, rootId, eventId)) return;
    if (!await _post(room, eventId, rootId, public: public)) return;
    if (mainTimeline != null) {
      await _refreshMainRead(mainTimeline, public: public);
    }
  }

  /// Vommet issue 704: Tuwunel's sliding sync only resends a room's unread
  /// counts when its main read position moves, so after a thread receipt the
  /// room and its space kept their unread marker until the room's next
  /// message. When the main timeline is already read up to its newest
  /// message (our last `main` receipt is on it), post that receipt again:
  /// it moves nothing, but makes the server send the cleared count. A main
  /// timeline with unread messages is left alone, since the server clears
  /// the room's main count on any main receipt.
  static Future<void> _refreshMainRead(matrix.Timeline timeline,
      {required bool public}) async {
    final room = timeline.room;
    final newest = newestMainEvent(timeline);
    if (newest == null || !_mainReadUpTo(room, newest)) return;
    await _post(room, newest.eventId, "main", public: public);
  }

  /// Vommet issue 843: whether the main timeline is read up to [newest].
  /// [_sent] is empty after a restart, so the stored receipts count too,
  /// and so does our own message (sending it reads the room).
  static bool _mainReadUpTo(matrix.Room room, matrix.Event newest) {
    if (_sent[room]?["main"] == newest.eventId) return true;
    if (newest.senderId == room.client.userID) return true;
    final receipts = room.receiptState;
    return [receipts.global, receipts.mainThread]
        .nonNulls
        .expand((r) => [r.ownPublic?.eventId, r.ownPrivate?.eventId])
        .contains(newest.eventId);
  }

  /// The main timeline's newest synced event that isn't a thread reply.
  static matrix.Event? newestMainEvent(matrix.Timeline timeline) =>
      timeline.events
          .firstWhereOrNull((e) => e.status.isSynced && !isThreadReply(e));

  static bool _alreadySent(matrix.Room room, String thread, String eventId) {
    final sent = _sent[room] ??= {};
    if (sent[thread] == eventId) return true;
    sent[thread] = eventId;
    return false;
  }

  static void _forgetSent(matrix.Room room, String thread, String eventId) {
    final sent = _sent[room];
    if (sent?[thread] == eventId) sent!.remove(thread);
  }

  /// Whether the receipt went through.
  static Future<bool> _post(matrix.Room room, String eventId, String threadId,
      {required bool public}) async {
    try {
      await room.client.postReceipt(
          room.id,
          public ? matrix.ReceiptType.mRead : matrix.ReceiptType.mReadPrivate,
          eventId,
          threadId: threadId);
    } catch (e, s) {
      _forgetSent(room, threadId, eventId);
      Log.onError(e, s, content: "Could not send a threaded read receipt");
      return false;
    }
    recordOwnReceipt(room, eventId, threadId: threadId);
    // Vommet issue 843: the server may not send the lowered unread count
    // again, so lower the room's count locally as well.
    try {
      await room.client.slidingSyncController.unreadCounts
          .onOwnReceipt(room, eventId, threadId: threadId);
    } catch (e, s) {
      Log.onError(e, s, content: "Could not update the room's unread count");
    }
    return true;
  }
}
