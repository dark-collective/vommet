import 'dart:async';

import 'package:matrix/matrix.dart' as matrix;

/// Vommet: per-room views of the SDK client's shared streams.
///
/// Every room (and space, and room emoji manager) used to listen to the
/// client's streams itself and filter for its own room id, so each state
/// change, event, notification and sync was delivered to every room: about
/// 500 deliveries per state change on a 237-room account, much of a phone's
/// startup freeze (startup telemetry and CPU profile, 2026-10-12). The
/// router listens once per stream and hands each item only to its room.
///
/// Delivery stays asynchronous and in order, as with the filtered streams.
/// A room's stream is created on first use and kept for the client's
/// lifetime (rooms are few and long-lived).
class RoomStreamRouter {
  static final Expando<RoomStreamRouter> _routers = Expando();

  /// The router for [client], created on first use.
  static RoomStreamRouter of(matrix.Client client) =>
      _routers[client] ??= RoomStreamRouter._(client);

  final _roomState = <String,
      StreamController<({String roomId, matrix.StrippedStateEvent state})>>{};
  // ignore: deprecated_member_use
  final _events = <String, StreamController<matrix.EventUpdate>>{};
  final _notifications = <String, StreamController<matrix.Event>>{};
  final _joinedSyncs = <String, StreamController<matrix.SyncUpdate>>{};

  RoomStreamRouter._(matrix.Client client) {
    client.onRoomState.stream
        .listen((update) => _roomState[update.roomId]?.add(update));
    // ignore: deprecated_member_use
    client.onEvent.stream
        .listen((update) => _events[update.roomID]?.add(update));
    client.onNotification.stream
        .listen((event) => _notifications[event.roomId]?.add(event));
    client.onSync.stream.listen((sync) {
      final join = sync.rooms?.join;
      if (join == null || _joinedSyncs.isEmpty) return;
      for (final roomId in join.keys) {
        _joinedSyncs[roomId]?.add(sync);
      }
    });
  }

  static Stream<T> _stream<T>(
          Map<String, StreamController<T>> map, String id) =>
      (map[id] ??= StreamController<T>.broadcast()).stream;

  /// `client.onRoomState` for one room.
  Stream<({String roomId, matrix.StrippedStateEvent state})> roomState(
          String roomId) =>
      _stream(_roomState, roomId);

  /// `client.onEvent` for one room.
  // ignore: deprecated_member_use
  Stream<matrix.EventUpdate> events(String roomId) => _stream(_events, roomId);

  /// `client.onNotification` for one room.
  Stream<matrix.Event> notifications(String roomId) =>
      _stream(_notifications, roomId);

  /// The syncs whose joined rooms include [roomId].
  Stream<matrix.SyncUpdate> joinedSyncs(String roomId) =>
      _stream(_joinedSyncs, roomId);
}
