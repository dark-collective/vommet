import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/client/matrix/matrix_space.dart';
import 'package:commet/debug/log.dart';
import 'package:matrix/matrix.dart' as matrix;

/// Vommet: m.room.tombstone for a Matrix room. Commet upstream ignores
/// tombstones (Commet upstream issue 482).
class MatrixRoomReplacement implements RoomReplacement {
  MatrixRoomReplacement(this.room);

  final MatrixRoom room;

  matrix.Room get _room => room.matrixRoom;
  matrix.Client get _mx => _room.client;

  /// Body sent when the user leaves the message empty (matches what servers
  /// write on /upgrade).
  static const fallbackBody = "This room has been replaced";

  @override
  RoomTombstone? get tombstone {
    final state = _room.getState(matrix.EventTypes.RoomTombstone);
    if (state == null) return null;
    return parseTombstone(state.content, senderId: state.senderId);
  }

  @override
  RoomPredecessor? get predecessor {
    final create = _room.getState(matrix.EventTypes.RoomCreate);
    final id = parsePredecessorRoomId(create?.content);
    if (id == null) return null;
    final sender = create!.senderId;
    return RoomPredecessor(
      roomId: id,
      upgradedBy:
          _room.unsafeGetUserFromMemoryOrFallback(sender).calcDisplayname(),
      upgradedAt: create is matrix.Event ? create.originServerTs : null,
    );
  }

  @override
  Room? get predecessorRoom {
    final id = predecessor?.roomId;
    if (id == null) return null;
    return room.client.getRoom(id);
  }

  @override
  String? get roomVersion => _room.roomVersion;

  @override
  bool get canReplace =>
      _room.membership == matrix.Membership.join &&
      _room.canChangeStateEvent(matrix.EventTypes.RoomTombstone);

  @override
  int get otherMemberCount {
    final joined = _room.summary.mJoinedMemberCount ??
        _room.getParticipants([matrix.Membership.join]).length;
    return joined > 0 ? joined - 1 : 0;
  }

  @override
  List<Space> get swappableSpaces => room.client.spaces
      .whereType<MatrixSpace>()
      .where((space) =>
          _childContent(space.matrixRoom) != null &&
          space.matrixRoom.canChangeStateEvent(matrix.EventTypes.SpaceChild))
      .toList();

  /// This room's m.space.child content in [space], when it lists the room.
  Map<String, Object?>? _childContent(matrix.Room space) {
    final content =
        space.getState(matrix.EventTypes.SpaceChild, _room.id)?.content;
    final via = content?["via"];
    if (via is! List || via.isEmpty) return null;
    return content;
  }

  @override
  Future<RoomVersionOptions?> getVersionOptions() async {
    final capabilities = await _mx.getCapabilities();
    final versions = capabilities.mRoomVersions;
    if (versions == null) return null;
    return RoomVersionOptions(
      defaultVersion: versions.default$,
      stable: [
        for (final e in versions.available.entries)
          if (e.value == matrix.RoomVersionAvailable.stable) e.key
      ],
      unstable: [
        for (final e in versions.available.entries)
          if (e.value == matrix.RoomVersionAvailable.unstable) e.key
      ],
    );
  }

  @override
  Future<String> upgrade(String version) async {
    final newRoomId = await _mx.upgradeRoom(_room.id, version);
    await _waitForRoom(newRoomId);
    return newRoomId;
  }

  @override
  Future<void> replaceWith(String roomId, {String? body}) async {
    await _mx.setRoomStateWithKey(_room.id, matrix.EventTypes.RoomTombstone, "",
        buildTombstoneContent(roomId, body, fallbackBody));
  }

  @override
  Future<void> swapInSpaces(String newRoomId, List<Space> spaces) async {
    final ownServer = _mx.userID?.domain;
    for (final space in spaces.whereType<MatrixSpace>()) {
      final mxSpace = space.matrixRoom;
      final old = _childContent(mxSpace);
      if (old == null) continue;
      final via = replacementVia(ownServer, old["via"]);

      await _mx.setRoomStateWithKey(mxSpace.id, matrix.EventTypes.SpaceChild,
          newRoomId, swappedSpaceChildContent(old, via));
      await _mx.setRoomStateWithKey(
          mxSpace.id, matrix.EventTypes.SpaceChild, _room.id, {});

      // The parent links are a nicety; the child list is what clients use.
      try {
        await _mx.setRoomStateWithKey(
            newRoomId, matrix.EventTypes.SpaceParent, mxSpace.id, {"via": via});
      } catch (e) {
        Log.w("Couldn't link the new room to its space: $e");
      }
      if (_room.getState(matrix.EventTypes.SpaceParent, mxSpace.id) != null) {
        try {
          await _mx.setRoomStateWithKey(
              _room.id, matrix.EventTypes.SpaceParent, mxSpace.id, {});
        } catch (e) {
          Log.w("Couldn't unlink the old room from its space: $e");
        }
      }
    }
  }

  @override
  Future<int> inviteMembersTo(String newRoomId) async {
    final joined = await _room.requestParticipants([matrix.Membership.join]);
    final target = _mx.getRoomById(newRoomId);
    final already = target
            ?.getParticipants(
                [matrix.Membership.join, matrix.Membership.invite])
            .map((u) => u.id)
            .toSet() ??
        <String>{};

    var failed = 0;
    for (final id
        in membersToInvite(joined.map((u) => u.id), _mx.userID!, already)) {
      try {
        await _mx.inviteUser(newRoomId, id);
      } catch (e) {
        failed++;
        Log.w("Couldn't invite $id to the new room: $e");
      }
    }
    return failed;
  }

  @override
  Future<Room> openReplacement() async {
    final stone = tombstone;
    if (stone == null) throw StateError("This room hasn't been replaced");
    final id = stone.replacementRoomId;
    final existing = room.client.getRoom(id);
    if (existing != null) return existing;

    final via = <String>{
      if (stone.senderId?.domain case final server?) server,
      if (_room.id.domain case final server?) server,
    };
    return room.client.joinRoom(via.isEmpty ? id : "$id?via=${via.join(",")}");
  }

  Future<void> _waitForRoom(String roomId) async {
    if (_mx.getRoomById(roomId)?.membership == matrix.Membership.join) return;
    try {
      await _mx
          .waitForRoomInSync(roomId, join: true)
          .timeout(const Duration(seconds: 30));
    } on TimeoutException {
      Log.w("The new room $roomId hasn't synced yet");
    }
  }
}
