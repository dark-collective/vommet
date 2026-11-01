import 'package:commet/client/room_unread_source.dart';
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
  final _positionQueue = LinkedHashMap<MatrixRoom, _UnreadWork>.identity();
  final _loadingPositions = HashSet<MatrixRoom>.identity();
  static const _positionConcurrency = 2;
  static const _highlightPageSize = 50;
  Timer? _positionDrain;
  Timer? _notification;
  bool _pending = false;
  bool _closed = false;

  RoomUnread room(Room room) => _closed
      ? const RoomUnread()
      : _values[room.localId] ??= computeRoomUnread(room);

  /// The physical rooms represented by a list row or pinned sidebar icon.
  List<Room> roomsForRow(Room room) {
    final dms = client.getComponent<DirectMessagesComponent>();
    final partner = dms?.getDirectMessagePartnerId(room);
    final group = partner == null ? <Room>[] : dms!.directMessagesWith(partner);
    return group.isEmpty ? [room] : group;
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
      final key = dms!.getDirectMessagePartnerId(r) ?? r.localId;
      if (seen.add(key)) yield (key, person(r));
    }
  }

  PersonUnread sum(Iterable<Room> rooms) =>
      UnreadTotals.rooms(rooms.map((r) => (r.localId, room(r))));

  void refresh() {
    if (_closed || _pending) return;
    _pending = true;
    scheduleMicrotask(() {
      _pending = false;
      if (_closed) return;
      final dmSource =
          client.getComponent<DirectMessagesComponent>()?.directMessageRooms;
      if (!identical(dmSource, _dmSource)) {
        _dmSubscription?.cancel();
        _dmSource = dmSource;
        _dmSubscription = dmSource?.onListUpdated.listen((_) => refresh());
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
      final current = HashSet<Room>.identity()..addAll(client.rooms);
      for (final r in _rooms.keys.toList()) {
        if (current.contains(r)) continue;
        _rooms.remove(r)?.cancel();
        _values.remove(r.localId);
        _positionsSignature.remove(r.localId);
        _positionQueue.remove(r);
      }
      for (final r in current) {
        _rooms.putIfAbsent(r, () => r.onUpdate.listen((_) => refresh()));
        _values[r.localId] = computeRoomUnread(r);
        if (r is MatrixRoom) _queuePositions(r);
      }
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
    final muted = _values[room.localId]?.muted == true;
    final receipts = ownReceiptIdsForOrder(mx).toSet().toList()..sort();
    if (muted ||
        (receipts.isEmpty && !(mx.encrypted && hasEmptyReadState(mx)))) {
      _positionQueue.remove(room);
      _positionsSignature.remove(room.localId);
      return;
    }
    final rules = mx.encrypted
        ? identityHashCode(mx.client.accountData[matrix.EventTypes.PushRules])
        : 0;
    final signature = '${mx.lastEvent?.eventId}/${room.lastEvent?.eventId}/'
        '${room.timeline?.events.length}/${receipts.join(",")}/${mx.fullyRead}/$rules/$_highlightEligibility';
    if (_positionsSignature[room.localId] == signature) return;
    _positionsSignature[room.localId] = signature;
    _positionQueue[room] = _UnreadWork(signature);
    _schedulePositionDrain();
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

  bool _currentWork(MatrixRoom room, String signature) =>
      !_closed &&
      _rooms.containsKey(room) &&
      _values[room.localId]?.muted != true &&
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
            final event = await database.getEventById(id, mx);
            if (event != null) events.add(event);
          }
          if (!_currentWork(room, signature)) return;
          if (size > 1) {
            events.addAll(
                await database.getEventList(mx, start: 1, limit: size - 1));
          }
        } else {
          events.addAll(
              await database.getEventList(mx, start: start, limit: size));
        }
        if (!_currentWork(room, signature)) return;
        room.restoreCachedHighlights(events);
        final next = start + _highlightPageSize;
        if (next < work.scanEnd) {
          _positionQueue[room] =
              _UnreadWork(signature, pageStart: next, scanEnd: work.scanEnd);
        }
      } else {
        // Read stored order without creating/loading another SDK timeline.
        final events = await database.getEventIdList(mx, limit: null);
        if (!_currentWork(room, signature)) return;
        orderChanged = rememberUnreadOrder(mx, events);
        if (mx.encrypted) {
          final end = cachedUnreadPrefixLength(mx);
          if (end > 0) {
            _positionQueue[room] =
                _UnreadWork(signature, pageStart: 0, scanEnd: end);
          }
        }
      }
      final previous = _values[room.localId];
      final next = computeRoomUnread(room);
      _values[room.localId] = next;
      if (orderChanged || previous != next) _notifyChanged();
    } catch (_) {
      // Exact ID receipts still work while storage is unavailable. Retry on sync.
      if (_currentWork(room, signature)) {
        _positionsSignature.remove(room.localId);
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
