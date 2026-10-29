import 'package:collection/collection.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:matrix/matrix.dart' as matrix;

/// Vommet: threaded read receipts (MSC3771), behind the "Read state per
/// thread" experiment.
///
/// With the experiment on, reading a thread sends a receipt for that thread,
/// and reading the room's main timeline sends a receipt for `main` instead
/// of an unthreaded one, so opening the room no longer marks every thread
/// read. Marking the whole room read (room list menu) stays unthreaded.
class ThreadReceipts {
  static bool get enabled => preferences.experimentThreadReadState.value;

  /// The last receipt sent per room and thread, so scrolling doesn't resend.
  static final Map<String, String> _sent = {};

  static bool isThreadReply(matrix.Event event) =>
      event.relationshipType == matrix.RelationshipTypes.thread;

  /// Marks the main timeline read up to its newest synced event that isn't
  /// a thread reply.
  static Future<void> markMainRead(matrix.Timeline timeline,
      {required bool public}) async {
    final event = newestMainEvent(timeline);
    if (event == null) return;
    final room = timeline.room;
    if (_alreadySent(room.id, "main", event.eventId)) return;
    await room.client.setReadMarker(room.id, mFullyRead: event.eventId);
    await _post(room, event.eventId, "main", public: public);
  }

  /// Marks thread [rootId] read up to [eventId]. [mainTimeline] is the
  /// room's main timeline, for [_refreshMainRead].
  static Future<void> markThreadRead(
      matrix.Room room, String rootId, String eventId,
      {required bool public, matrix.Timeline? mainTimeline}) async {
    if (eventId == rootId) return;
    if (_alreadySent(room.id, rootId, eventId)) return;
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
    if (newest == null || _sent["${room.id}|main"] != newest.eventId) return;
    await _post(room, newest.eventId, "main", public: public);
  }

  /// The main timeline's newest synced event that isn't a thread reply.
  static matrix.Event? newestMainEvent(matrix.Timeline timeline) =>
      timeline.events
          .firstWhereOrNull((e) => e.status.isSynced && !isThreadReply(e));

  static bool _alreadySent(String roomId, String thread, String eventId) {
    final key = "$roomId|$thread";
    if (_sent[key] == eventId) return true;
    _sent[key] = eventId;
    return false;
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
      return true;
    } catch (e, s) {
      _sent.remove("${room.id}|$threadId");
      Log.onError(e, s, content: "Could not send a threaded read receipt");
      return false;
    }
  }
}
