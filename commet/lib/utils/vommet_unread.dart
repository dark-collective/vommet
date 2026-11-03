import 'package:commet/client/components/message_filters/message_filters.dart';
import 'package:commet/client/components/user_blocking/user_blocking_component.dart';

import 'package:commet/client/client.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event.dart';
import 'package:matrix/matrix.dart' as matrix;

import 'package:commet/utils/unread_index.dart';

/// Event types that make a room unread. Call membership and the call
/// signalling events are left out: in a voice room they're the newest
/// event every time someone joins, leaves or refreshes their membership
/// (bridged voice users do this often), which kept the mark lit with
/// nothing new to read. Discord doesn't mark a channel unread when
/// someone joins voice either. A call invite still counts.
const _unreadTypes = {
  matrix.EventTypes.Message,
  matrix.EventTypes.Encrypted,
  matrix.EventTypes.Sticker,
  matrix.EventTypes.CallInvite,
};

/// The SDK's hasNewMessages, but a read receipt for the main thread counts
/// too: with per-thread read state on, Vommet only sends those, and the SDK
/// reads only unthreaded receipts, so the room never looked read. When the
/// newest event is a call event, the newest message is judged instead.
bool roomHasUnreadActivity(MatrixRoom matrixRoom) {
  final room = matrixRoom.matrixRoom;
  final last = unreadActivityEvent(matrixRoom)?.event;
  if (last == null || last.senderId == room.client.userID) return false;
  return !readByOwnReceipts(room, last);
}

/// The exact visible, synced event used by the activity model and debug dump.
MatrixTimelineEvent? unreadActivityEvent(MatrixRoom matrixRoom) {
  final candidates = <MatrixTimelineEvent>[
    if (matrixRoom.lastEvent case final MatrixTimelineEvent event) event,
    if (matrixRoom.lastMessage case final MatrixTimelineEvent event) event,
    ...?matrixRoom.timeline?.events.whereType<MatrixTimelineEvent>(),
  ];
  // The room's newest preview is authoritative. The receipt-order cache may
  // lag sync; it must not demote that preview in favor of an older event
  // whose position happens to be cached.
  for (final candidate in candidates) {
    final last = candidate.event;
    if (!_unreadTypes.contains(last.type) ||
        last.redacted ||
        last.relationshipType == 'm.replace' ||
        !last.status.isSynced) continue;
    if (matrixRoom.client
                .getComponent<UserBlockingComponent>()
                ?.isBlocked(last.senderId) ==
            true ||
        MessageFilters.hidesEverywhere(matrixRoom, candidate)) continue;
    return candidate;
  }
  return null;
}

/// Whether the account's own read receipts cover [event]: one is on it or
/// came later. A thread reply is also covered by its thread's receipt.
bool readByOwnReceipts(matrix.Room room, matrix.Event event) {
  return receiptCovers(
      event.eventId, ownReceiptIds(room, event), _knownOrder[room] ?? const []);
}

final _knownOrder = Expando<List<String>>();
List<String> unreadOrder(matrix.Room room) => _knownOrder[room] ?? const [];
bool rememberUnreadOrder(matrix.Room room, List<String> newestFirst) {
  final previous = unreadOrder(room);
  var changed = previous.length != newestFirst.length;
  for (var i = 0; !changed && i < previous.length; i++) {
    changed = previous[i] != newestFirst[i];
  }
  _knownOrder[room] = newestFirst;
  return changed;
}

final _localReceipts = Expando<Map<String, String>>();

/// Capture the SDK's newest synced event before the request yields. A newer
/// event (or a pending outgoing event) is not acknowledged by this request.
Future<void> markTimelineRead(matrix.Timeline timeline, {bool? public}) async {
  final id = timeline.events
      .where((event) => event.status.isSynced)
      .firstOrNull
      ?.eventId;
  if (id == null) return;
  await timeline.setReadMarker(eventId: id, public: public);
  recordOwnReceipt(timeline.room, id);
}

/// All scopes, only for invalidating cached order. Receipt coverage still
/// uses the scopes applicable to the particular event being compared.
Iterable<String> ownReceiptIdsForOrder(matrix.Room room) sync* {
  yield* _ownReceipts(room).map((receipt) => receipt.eventId);
  for (final thread in room.receiptState.byThread.values) {
    for (final receipt in [thread.ownPublic, thread.ownPrivate].nonNulls) {
      yield receipt.eventId;
    }
  }
  yield* (_localReceipts[room] ?? const <String, String>{}).values;
}

/// A successful receipt clears local dots and encrypted highlights immediately,
/// even before the server echoes it or supplies another unread count.
void recordOwnReceipt(matrix.Room room, String eventId, {String? threadId}) {
  (_localReceipts[room] ??= {})[threadId ?? 'unthreaded'] = eventId;
  UnreadIndex.receiptChanged(room);
}

Iterable<String> ownReceiptIdsForThread(matrix.Room room, String? root) sync* {
  yield* _ownReceipts(room, root).map((receipt) => receipt.eventId);
  yield* _localOwnReceiptIds(room, root);
}

Iterable<String> ownReceiptIds(matrix.Room room, [matrix.Event? event]) sync* {
  final root = event?.relationshipType == matrix.RelationshipTypes.thread
      ? event?.relationshipEventId
      : null;
  yield* ownReceiptIdsForThread(room, root);
}

bool hasLocalOwnReceipt(matrix.Room room, [matrix.Event? event]) =>
    _localOwnReceiptIds(
            room,
            event?.relationshipType == matrix.RelationshipTypes.thread
                ? event?.relationshipEventId
                : null)
        .isNotEmpty;

Iterable<String> _localOwnReceiptIds(matrix.Room room, String? root) sync* {
  final local = _localReceipts[room] ?? const <String, String>{};
  for (final key in ['unthreaded', root ?? 'main']) {
    final id = local[key];
    if (id != null) yield id;
  }
}

Iterable<matrix.LatestReceiptStateData> _ownReceipts(matrix.Room room,
        [String? root]) =>
    [
      room.receiptState.global.ownPublic,
      room.receiptState.global.ownPrivate,
      if (root == null) ...[
        room.receiptState.mainThread?.ownPublic,
        room.receiptState.mainThread?.ownPrivate,
      ] else ...[
        room.receiptState.byThread[root]?.ownPublic,
        room.receiptState.byThread[root]?.ownPrivate,
      ],
    ].nonNulls;

/// An empty read state follows the activity model's absence policy. A marker
/// without receipts is ambiguous, and existing unknown receipt IDs stay unknown.
bool hasEmptyReadState(matrix.Room room) =>
    ownReceiptIdsForOrder(room).isEmpty && room.fullyRead.isEmpty;

int _cachedJoinBoundary(matrix.Room room) {
  final order = unreadOrder(room);
  final join =
      room.getState(matrix.EventTypes.RoomMember, room.client.userID ?? '');
  final at = join is matrix.Event && join.content['membership'] == 'join'
      ? order.indexOf(join.eventId)
      : -1;
  return at < 0 ? order.length : at;
}

/// Historical payloads need known positions. No receipts and no marker is
/// unread by the same policy as room activity; missing existing receipt IDs
/// never become proof of unread. A known join excludes pre-join history.
bool cachedEventIsUnread(matrix.Room room, matrix.Event event) {
  final order = unreadOrder(room);
  final at = order.indexOf(event.eventId);
  if (at < 0 || at >= _cachedJoinBoundary(room)) return false;
  return receiptCoverage(event.eventId, ownReceiptIds(room, event), order) ==
          false ||
      hasEmptyReadState(room);
}

/// Bounds cached payload recovery to positions that could be definitely
/// unread in at least one known receipt scope. Every payload is still checked
/// against its own scope; the fully-read marker is not a read receipt.
int cachedUnreadPrefixLength(matrix.Room room) {
  final order = unreadOrder(room);
  if (hasEmptyReadState(room)) return _cachedJoinBoundary(room);
  int? knownPosition(Iterable<String> ids) {
    var end = order.length;
    var any = false;
    for (final id in ids) {
      any = true;
      final at = order.indexOf(id);
      if (at < 0) return null;
      if (at < end) end = at;
    }
    return any ? end : null;
  }

  final local = _localReceipts[room] ?? const <String, String>{};
  final global = <String>[
    for (final receipt in [
      room.receiptState.global.ownPublic,
      room.receiptState.global.ownPrivate
    ].nonNulls)
      receipt.eventId,
    if (local['unthreaded'] case final id?) id,
  ];
  if (global.isNotEmpty) return knownPosition(global) ?? 0;
  var end = 0;
  final roots = <String?>{
    null,
    ...room.receiptState.byThread.keys,
    ...local.keys.where((key) => key != 'main' && key != 'unthreaded'),
  };
  for (final root in roots) {
    final at = knownPosition(ownReceiptIdsForThread(room, root));
    if (at != null && at > end) end = at;
  }
  return end;
}

/// Whether any room in [space] or its subspaces is unread (false while the
/// space is muted).
bool spaceHasUnread(Space space) => space.unread.unread;
