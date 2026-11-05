import 'package:commet/client/room_unread_source.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/client/components/user_blocking/user_blocking_component.dart';
import 'package:commet/client/components/message_filters/message_filters.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'dart:async';
import 'dart:collection';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/client/components/emoticon/emoticon_component.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/utils/room_unread.dart';
import 'package:commet/utils/vommet_unread.dart';

export 'package:commet/utils/room_unread.dart';

class _UnreadWork {
  const _UnreadWork(this.signature, {this.pageStart, this.scanEnd = 0});
  final String signature;
  final int? pageStart;
  final int scanEnd;
}

/// One account's unread state. Receipts, account data, push rules, decrypted
/// mentions and DM changes converge here before any surface is notified.
class UnreadIndex {
  static final _accounts = Expando<UnreadIndex>();
  static UnreadIndex of(Client client) =>
      _accounts[client] ??= UnreadIndex._(client);
  static Future<void> disposeFor(Client client) async {
    await _accounts[client]?.dispose();
  }

  static RoomUnread roomOf(Room room) => of(room.client).room(room);
  static PersonUnread rowOf(Room room) => of(room.client).person(room);

  static final _sdkAccounts = Expando<UnreadIndex>();
  static void receiptChanged(matrix.Room room) =>
      _sdkAccounts[room.client]?.refresh();

  UnreadIndex._(this.client) {
    if (client is MatrixClient) {
      _sdkAccounts[(client as MatrixClient).matrixClient] = this;
    }
    _subscriptions.addAll([
      client.onSync.listen((_) => refresh()),
      client.onRoomAdded.listen((_) => refresh()),
      client.onRoomRemoved.listen((_) => refresh()),
    ]);
    MessageFilters.changed.addListener(refresh);
    refresh();
  }
  final Client client;
  final _changed = StreamController<void>.broadcast();
  Stream<void> get onChanged => _changed.stream;
  final _values = <String, RoomUnread>{};
  final _rooms = HashMap<Room, StreamSubscription>.identity();
  final _subscriptions = <StreamSubscription>[];
  Object? _blockingSource;
  StreamSubscription? _blockingSubscription;
  String _highlightEligibility = '';
  Object? _dmSource;
  StreamSubscription? _dmSubscription;
  final _positionsSignature = <String, String>{};
  // Per room object (a replaced wrapper starts with no cached mentions): the
  // read evidence a cached-mention scan ran under, the newest event it
  // started from, and how many positions from there are done. Newer events
  // are counted live, so only new evidence restarts the scan.
  final _scans = HashMap<Room, (String, String, int)>.identity();
  final _positionQueue = LinkedHashMap<MatrixRoom, _UnreadWork>.identity();
  final _loadingPositions = HashSet<MatrixRoom>.identity();
  static const _positionConcurrency = 2;
  static const _highlightPageSize = 50;
  // Receipts further back than this are unknown positions, as for a room
  // whose older history is not stored.
  static const _orderWindow = 1000;
  Timer? _positionDrain;
  Timer? _notification;
  bool _pending = false;
  bool _refreshAll = false;
  bool _emit = false;
  final _dirty = HashSet<Room>.identity();
  // Read evidence per room: entry read states can change with it while the
  // room's own counts stay the same.
  final _readState = <String, String>{};
  bool _closed = false;

  // Only listed rooms are kept up to date; any other room is computed on
  // demand so a stale value can never be served for it.
  RoomUnread room(Room room) => _closed
      ? const RoomUnread()
      : _rooms.containsKey(room)
          ? _values[room.localId] ??= _compute(room) ?? const RoomUnread()
          : _compute(room) ?? const RoomUnread();

  RoomUnread? _compute(Room room) {
    try {
      return computeRoomUnread(room);
    } catch (error, trace) {
      Log.onError(error, trace, content: "Unread state failed: $error");
      return null;
    }
  }

  /// The physical rooms represented by a list row or pinned sidebar icon.
  /// Only the room shown for a person stands for the whole group; an older
  /// DM room listed on its own (in a space, say) is just itself.
  List<Room> roomsForRow(Room room) {
    final dms = client.getComponent<DirectMessagesComponent>();
    final partner = dms?.getDirectMessagePartnerId(room);
    final group = partner == null ? <Room>[] : dms!.directMessagesWith(partner);
    return group.isNotEmpty && identical(group.first, room) ? group : [room];
  }

  PersonUnread person(Room room) =>
      PersonUnread.of(roomsForRow(room).map(this.room));

  Iterable<(String, PersonUnread)> get people sync* {
    final dms = client.getComponent<DirectMessagesComponent>();
    final seen = <String>{};
    for (final r in client.rooms) {
      if (dms?.isRoomDirectMessage(r) != true ||
          isSupersededRoom(r) ||
          isStickerRoom(r)) continue;
      final partner = dms!.getDirectMessagePartnerId(r);
      final key = partner ?? r.localId;
      if (!seen.add(key)) continue;
      // The whole person, whichever of their rooms comes first here: only
      // the newest one stands for the group in roomsForRow.
      final group =
          partner == null ? const <Room>[] : dms.directMessagesWith(partner);
      yield (key, PersonUnread.of((group.isEmpty ? [r] : group).map(room)));
    }
  }

  PersonUnread sum(Iterable<Room> rooms) =>
      UnreadTotals.rooms(rooms.map((r) => (r.localId, room(r))));

  void refresh() {
    _refreshAll = true;
    _schedule();
  }

  void _roomUpdated(Room room) {
    _dirty.add(room);
    _schedule();
  }

  void _listChanged() {
    // Row grouping can change without any room's own value changing.
    _emit = true;
    refresh();
  }

  void _schedule() {
    if (_closed || _pending) return;
    _pending = true;
    scheduleMicrotask(() {
      _pending = false;
      if (_closed) return;
      var changed = _emit;
      final all = _refreshAll;
      final dirty = _dirty.toList();
      _emit = _refreshAll = false;
      _dirty.clear();
      final dmSource =
          client.getComponent<DirectMessagesComponent>()?.directMessageRooms;
      if (!identical(dmSource, _dmSource)) {
        _dmSubscription?.cancel();
        _dmSource = dmSource;
        _dmSubscription = dmSource?.onListUpdated.listen((_) => _listChanged());
      }
      final blocking = client.getComponent<UserBlockingComponent>();
      if (!identical(blocking, _blockingSource)) {
        _blockingSubscription?.cancel();
        _blockingSource = blocking;
        _blockingSubscription = blocking?.onChanged.listen((_) => refresh());
      }
      if (client is MatrixClient) {
        final mx = (client as MatrixClient).matrixClient;
        final blocked = (blocking?.blockedUsers.toList() ?? <String>[])..sort();
        _highlightEligibility =
            '${identityHashCode(mx.accountData[MessageFilters.type])}/${blocked.join(",")}';
      }
      final Iterable<Room> update;
      if (all) {
        final current = HashSet<Room>.identity()..addAll(client.rooms);
        for (final r in _rooms.keys.toList()) {
          if (current.contains(r)) continue;
          _rooms.remove(r)?.cancel();
          _values.remove(r.localId);
          _readState.remove(r.localId);
          _positionsSignature.remove(r.localId);
          _scans.remove(r);
          _positionQueue.remove(r);
          changed = true;
        }
        update = current;
      } else {
        update = dirty.where(_rooms.containsKey);
      }
      for (final r in update) {
        _rooms.putIfAbsent(r, () => r.onUpdate.listen((_) => _roomUpdated(r)));
        // A room that fails keeps its previous value; the rest still update.
        final next = _compute(r) ?? _values[r.localId];
        if (next == null) continue;
        if (_values[r.localId] != next) changed = true;
        _values[r.localId] = next;
        if (r is MatrixRoom) {
          final mx = r.matrixRoom;
          final read = '${ownReceiptIdsForOrder(mx).join(",")}/${mx.fullyRead}';
          if (_readState[r.localId] != read) changed = true;
          _readState[r.localId] = read;
          _queuePositions(r);
        }
      }
      if (!changed) return;
      _notification?.cancel();
      _notification = null;
      _changed.add(null);
    });
  }

  void _notifyChanged() {
    if (_closed || _notification != null) return;
    // Storage completions can arrive one per room. Publish one update per
    // burst so account-wide consumers do not rescan the account for each one.
    _notification = Timer(const Duration(milliseconds: 50), () {
      _notification = null;
      if (!_closed) _changed.add(null);
    });
  }

  void _queuePositions(MatrixRoom room) {
    final mx = room.matrixRoom;
    // The server never highlights in a muted room, so every muted room needs
    // the cached-mention scan, but only from a known receipt: no
    // full-history recovery for a muted room.
    final muted = _values[room.localId]?.muted == true;
    final noReceipt = ownReceiptIdsForOrder(mx).isEmpty;
    if ((muted && noReceipt) ||
        (noReceipt && !(mx.encrypted && hasEmptyReadState(mx)))) {
      _positionQueue.remove(room);
      _positionsSignature.remove(room.localId);
      _scans.remove(room);
      return;
    }
    final evidence = _readEvidence(room);
    // Forget scan progress as soon as evidence changes, even if this work is
    // replaced before it runs: the room may already have dropped mentions.
    if (_scans[room]?.$1 != evidence) _scans.remove(room);
    final signature = '${mx.lastEvent?.eventId}/${room.lastEvent?.eventId}/'
        '${room.timeline?.events.length}/$evidence';
    if (_positionsSignature[room.localId] == signature) return;
    _positionsSignature[room.localId] = signature;
    _positionQueue[room] = _UnreadWork(signature);
    _schedulePositionDrain();
  }

  String _readEvidence(MatrixRoom room) {
    final mx = room.matrixRoom;
    final receipts = ownReceiptIdsForOrder(mx).toSet().toList()..sort();
    final rules = mx.encrypted || _scansMuted(room)
        ? identityHashCode(mx.client.accountData[matrix.EventTypes.PushRules])
        : 0;
    return '${receipts.join(",")}/${mx.fullyRead}/$rules/$_highlightEligibility';
  }

  /// Where the cached-mention scan continues after the stored order reloads.
  int _scanStart(MatrixRoom room) {
    final order = unreadOrder(room.matrixRoom);
    final evidence = _readEvidence(room);
    if (_scans[room] case (final e, final newest, final done)
        when e == evidence) {
      final at = orderPosition(order, newest);
      if (at >= 0) return at + done;
    }
    if (order.isEmpty) return 0;
    _scans[room] = (evidence, order.first, 0);
    return 0;
  }

  void _schedulePositionDrain() {
    if (_closed || _positionDrain != null || _positionQueue.isEmpty) return;
    // Yield between storage batches, including synchronous cached results.
    _positionDrain = Timer(Duration.zero, () {
      _positionDrain = null;
      while (!_closed && _loadingPositions.length < _positionConcurrency) {
        final room = _positionQueue.keys
            .where((room) => !_loadingPositions.contains(room))
            .firstOrNull;
        if (room == null) break;
        final work = _positionQueue.remove(room)!;
        _loadingPositions.add(room);
        unawaited(_loadPositions(room, work));
      }
    });
  }

  /// Storage reads of the position and cached-mention scans, for tests.
  static int debugStorageReads = 0;

  static bool _ownMemberKnown(matrix.Room mx) =>
      mx.getState(matrix.EventTypes.RoomMember, mx.client.userID ?? '') != null;

  bool _scansMuted(MatrixRoom room) => _values[room.localId]?.muted == true;

  bool _currentWork(MatrixRoom room, String signature) =>
      !_closed &&
      _rooms.containsKey(room) &&
      _positionsSignature[room.localId] == signature;

  Future<void> _loadPositions(MatrixRoom room, _UnreadWork work) async {
    final mx = room.matrixRoom;
    final signature = work.signature;
    try {
      final database = (client as MatrixClient).matrixClient.database;
      var orderChanged = false;
      if (work.pageStart case final start?) {
        // Only stored payloads: no timeline creation, history requests or key
        // requests. Requeue each page behind other rooms to keep startup fair.
        final remaining = work.scanEnd - start;
        final size =
            remaining < _highlightPageSize ? remaining : _highlightPageSize;
        final events = <matrix.Event>[];
        if (start == 0) {
          // getEventList(start:0) prepends every pending send regardless of
          // limit. Load the first synced ID separately, then use a positive
          // offset so a large send queue cannot make recovery unbounded.
          final id = unreadOrder(mx).firstOrNull;
          if (id != null) {
            debugStorageReads++;
            final event = await database.getEventById(id, mx);
            if (event != null) events.add(event);
          }
          if (!_currentWork(room, signature)) return;
          if (size > 1) {
            debugStorageReads++;
            events.addAll(
                await database.getEventList(mx, start: 1, limit: size - 1));
          }
        } else {
          debugStorageReads++;
          events.addAll(
              await database.getEventList(mx, start: start, limit: size));
        }
        if (!_currentWork(room, signature)) return;
        room.restoreCachedHighlights(events);
        final next = start + _highlightPageSize;
        if (_scans[room] case (final e, final newest, _)) {
          final at = orderPosition(unreadOrder(mx), newest);
          if (at >= 0) {
            final done = next < work.scanEnd ? next : work.scanEnd;
            _scans[room] = (e, newest, done - at);
          }
        }
        if (next < work.scanEnd) {
          _positionQueue[room] =
              _UnreadWork(signature, pageStart: next, scanEnd: work.scanEnd);
        }
      } else {
        // A name mention needs our member event, which a partial room
        // (new, or not opened since a restart) doesn't keep in memory.
        if ((mx.encrypted || _scansMuted(room)) && !_ownMemberKnown(mx)) {
          await room.loadOwnMember();
          if (!_currentWork(room, signature)) return;
        }
        // Read stored order without creating/loading another SDK timeline.
        debugStorageReads++;
        final events = await database.getEventIdList(mx, limit: _orderWindow);
        if (!_currentWork(room, signature)) return;
        orderChanged = rememberUnreadOrder(mx, events);
        if (mx.encrypted || _scansMuted(room)) {
          final end = cachedUnreadPrefixLength(mx);
          final start = _scanStart(room);
          if (start < end) {
            _positionQueue[room] =
                _UnreadWork(signature, pageStart: start, scanEnd: end);
          }
        }
      }
      final previous = _values[room.localId];
      final next = _compute(room) ?? previous ?? const RoomUnread();
      _values[room.localId] = next;
      if (orderChanged || previous != next) _notifyChanged();
    } catch (_) {
      // Exact ID receipts still work while storage is unavailable. Retry on sync.
      if (_currentWork(room, signature)) {
        _positionsSignature.remove(room.localId);
        _scans.remove(room);
      }
    } finally {
      _loadingPositions.remove(room);
      _schedulePositionDrain();
    }
  }

  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    _positionDrain?.cancel();
    _notification?.cancel();
    _positionQueue.clear();
    MessageFilters.changed.removeListener(refresh);
    await _blockingSubscription?.cancel();
    await _dmSubscription?.cancel();
    for (final sub in [..._subscriptions, ..._rooms.values]) {
      await sub.cancel();
    }
    _rooms.clear();
    _values.clear();
    _readState.clear();
    _scans.clear();
    // Keep the closed index until the account is removed from the UI.
    // A rebuild during logout must not create fresh subscriptions.
    if (client is MatrixClient) {
      _sdkAccounts[(client as MatrixClient).matrixClient] = null;
    }
    // A UI consumer can be paused during logout; closing it must not hold
    // the account on screen until that consumer resumes.
    unawaited(_changed.close());
  }
}
