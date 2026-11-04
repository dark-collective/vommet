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
  final covered = receiptCoverage(
      last.eventId, ownReceiptIds(room, last), _knownOrder[room] ?? const []);
  if (covered != null) return !covered;
  // Vommet (voice rooms): where this device can't place the message or the
  // receipt, Discord's rule decides: read when we read the room after the
  // message came. In a voice room the receipt is mostly on a call or member
  // event (the newest when it was read) that a gappy sync or another device
  // never stored here, so every join lit the dot with nothing new to read.
  return !readAfter(room, last);
}

/// Whether one of the account's own server receipts that applies to
/// [event] was sent after it.
bool readAfter(matrix.Room room, matrix.Event event, {bool byTime = true}) {
  final root = event.relationshipType == matrix.RelationshipTypes.thread
      ? event.relationshipEventId
      : null;
  // A receipt this device can't place counts when it was sent after the
  // message and, for a message that arrived here this session, reached us
  // after the message did: a slow federated server can deliver a message
  // minutes after its origin_server_ts, after a receipt from another device.
  // A message held here since before this session is judged only once a
  // gap dropped it from the stored order, as before.
  final sent = event.originServerTs.millisecondsSinceEpoch;
  final floor = _receiptAtArrival[room]?[event.eventId];
  final known = orderPosition(unreadOrder(room), event.eventId) >= 0;
  if (byTime &&
      (floor != null || !known) &&
      _ownReceipts(room, root)
          .any((receipt) => receipt.ts > sent && receipt.ts > (floor ?? 0))) {
    return true;
  }
  // Marked read on this device: Mark as read puts the receipt on the newest
  // event. In a voice room that's a call or member event, and after a
  // limited sync the message isn't in the stored order to compare it with.
  return _markedRead[room]?.contains(event.eventId) == true;
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
bool readByOwnReceipts(matrix.Room room, matrix.Event event,
    {bool byTime = true}) {
  // Vommet: an unknown position falls back to [readAfter], like the room
  // dot, so the Unread card and thread dots agree with it. Mention counts
  // pass byTime: false and only take what was marked read here.
  return receiptCoverage(event.eventId, ownReceiptIds(room, event),
          _knownOrder[room] ?? const []) ??
      readAfter(room, event, byTime: byTime);
}

final _knownOrder = Expando<List<String>>();
List<String> unreadOrder(matrix.Room room) => _knownOrder[room] ?? const [];
bool rememberUnreadOrder(matrix.Room room, List<String> newestFirst) {
  final previous = unreadOrder(room);
  var changed = previous.length != newestFirst.length;
  for (var i = 0; !changed && i < previous.length; i++) {
    changed = previous[i] != newestFirst[i];
  }
  if (!changed) return false;
  final order = List<String>.unmodifiable(newestFirst);
  indexOrder(order);
  _knownOrder[room] = order;
  return true;
}

final _localReceipts = Expando<Map<String, String>>();

/// Vommet: for events that arrived this session, the newest own receipt time
/// this device had when they arrived; and that time after the last sync.
final _receiptAtArrival = Expando<Map<String, int>>();
final _receiptsSeen = Expando<int>();
const _arrivalsKept = 400;

/// Records, at each sync, the receipt each new event arrived after. Runs on
/// the sync itself: the unread index reads the stored order later, and a
/// burst of syncs could bring the receipt and the message before that.
void recordReceiptArrivals(matrix.Client client, matrix.SyncUpdate update) {
  for (final MapEntry(:key, :value)
      in (update.rooms?.join ?? const {}).entries) {
    final room = client.getRoomById(key);
    if (room == null) continue;
    final before = _receiptsSeen[room];
    _receiptsSeen[room] = _newestOwnReceiptTs(room);
    // The room's first sync this session: nothing to compare with.
    if (before == null) continue;
    final arrived = _receiptAtArrival[room] ??= <String, int>{};
    for (final event in value.timeline?.events ?? const []) {
      arrived.putIfAbsent(event.eventId, () => before);
    }
    if (arrived.length > _arrivalsKept) {
      arrived.keys
          .take(arrived.length - _arrivalsKept)
          .toList()
          .forEach(arrived.remove);
    }
  }
}

int _newestOwnReceiptTs(matrix.Room room) {
  var newest = 0;
  for (final receipt in [
    ..._ownReceipts(room),
    for (final thread in room.receiptState.byThread.values)
      ...[thread.ownPublic, thread.ownPrivate].nonNulls,
  ]) {
    if (receipt.ts > newest) newest = receipt.ts;
  }
  return newest;
}

/// Vommet: events read by a Mark as read on this device, for [readAfter].
final _markedRead = Expando<Set<String>>();

/// Records that the user marked [ids] read on this device. They stay read
/// even where their position isn't known.
void recordMarkedRead(matrix.Room room, Iterable<String> ids) {
  final read = _markedRead[room] ??= <String>{};
  read.addAll(ids);
  if (read.length > _arrivalsKept) {
    _markedRead[room] = read.skip(read.length - _arrivalsKept).toSet();
  }
}

/// Capture the SDK's newest synced event before the request yields. A newer
/// event (or a pending outgoing event) is not acknowledged by this request.
Future<void> markTimelineRead(matrix.Timeline timeline, {bool? public}) async {
  final id = timeline.events
      .where((event) => event.status.isSynced)
      .firstOrNull
      ?.eventId;
  if (id == null) return;
  final read = [
    for (final event in timeline.events)
      if (event.status.isSynced) event.eventId,
  ];
  await timeline.setReadMarker(eventId: id, public: public);
  recordMarkedRead(timeline.room, read);
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

/// The position of the event where our membership became join. Our newest
/// member event is often a later name or avatar change; the join itself is
/// then older than it and unknown, so the whole stored order counts.
int cachedJoinBoundary(matrix.Room room) {
  final order = unreadOrder(room);
  final join =
      room.getState(matrix.EventTypes.RoomMember, room.client.userID ?? '');
  if (join is! matrix.Event || join.content['membership'] != 'join') {
    return order.length;
  }
  final previous = join.prevContent ?? join.unsigned?['prev_content'];
  if (previous is Map && previous['membership'] == 'join') return order.length;
  final at = orderPosition(order, join.eventId);
  return at < 0 ? order.length : at;
}

/// Historical payloads need known positions. No receipts and no marker is
/// unread by the same policy as room activity; missing existing receipt IDs
/// never become proof of unread. A known join excludes pre-join history.
/// [joinBoundary] lets a caller checking a page compute it once.
bool cachedEventIsUnread(matrix.Room room, matrix.Event event,
    {int? joinBoundary}) {
  final order = unreadOrder(room);
  final at = orderPosition(order, event.eventId);
  if (at < 0 || at >= (joinBoundary ?? cachedJoinBoundary(room))) {
    return false;
  }
  return receiptCoverage(event.eventId, ownReceiptIds(room, event), order) ==
          false ||
      hasEmptyReadState(room);
}

/// Bounds cached payload recovery to positions that could be definitely
/// unread in at least one known receipt scope. Every payload is still checked
/// against its own scope; the fully-read marker is not a read receipt.
int cachedUnreadPrefixLength(matrix.Room room) {
  final order = unreadOrder(room);
  if (hasEmptyReadState(room)) return cachedJoinBoundary(room);
  int? knownPosition(Iterable<String> ids) {
    var end = order.length;
    var any = false;
    for (final id in ids) {
      any = true;
      final at = orderPosition(order, id);
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
