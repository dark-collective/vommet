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
    final event = timeline.events
        .firstWhereOrNull((e) => e.status.isSynced && !isThreadReply(e));
    if (event == null) return;
    final room = timeline.room;
    if (_alreadySent(room.id, "main", event.eventId)) return;
    await room.client.setReadMarker(room.id, mFullyRead: event.eventId);
    await _post(room, event.eventId, "main", public: public);
  }

  /// Marks thread [rootId] read up to [eventId].
  static Future<void> markThreadRead(
      matrix.Room room, String rootId, String eventId,
      {required bool public}) async {
    if (eventId == rootId) return;
    if (_alreadySent(room.id, rootId, eventId)) return;
    await _post(room, eventId, rootId, public: public);
  }

  static bool _alreadySent(String roomId, String thread, String eventId) {
    final key = "$roomId|$thread";
    if (_sent[key] == eventId) return true;
    _sent[key] = eventId;
    return false;
  }

  static Future<void> _post(matrix.Room room, String eventId, String threadId,
      {required bool public}) async {
    try {
      await room.client.postReceipt(
          room.id,
          public ? matrix.ReceiptType.mRead : matrix.ReceiptType.mReadPrivate,
          eventId,
          threadId: threadId);
    } catch (e, s) {
      _sent.remove("${room.id}|$threadId");
      Log.onError(e, s, content: "Could not send a threaded read receipt");
    }
  }
}
