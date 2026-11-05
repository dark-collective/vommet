import 'package:commet/client/client.dart';
import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/client/components/mutual_rooms/mutual_rooms_component.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/debug/log.dart';
import 'package:matrix/matrix.dart' as matrix;

/// Vommet: asks the homeserver (MSC2666) when it supports it, otherwise
/// checks the member lists of rooms we're already in.
class MatrixMutualRoomsComponent implements MutualRoomsComponent<MatrixClient> {
  @override
  MatrixClient client;

  MatrixMutualRoomsComponent(this.client);

  static const _feature = "uk.half-shot.msc2666.query_mutual_rooms";
  static const _path =
      "/client/unstable/uk.half-shot.msc2666/user/mutual_rooms";

  bool? _serverSupported;

  Future<bool> _serverSupports() async {
    if (_serverSupported != null) return _serverSupported!;
    try {
      final versions = await client.matrixClient.getVersions();
      final features = versions.unstableFeatures ?? {};
      _serverSupported =
          features[_feature] == true || features["$_feature.stable"] == true;
    } catch (e, s) {
      Log.onError(e, s, content: "Could not read homeserver versions");
      return false;
    }
    return _serverSupported!;
  }

  Future<Set<String>?> _fromServer(String userId) async {
    final ids = <String>{};
    String? from;
    // A few pages at most; each page is a list of room ids.
    for (var page = 0; page < 10; page++) {
      final result = await client.matrixClient.request(
          matrix.RequestType.GET, _path,
          query: {"user_id": userId, if (from != null) "from": from});
      final joined = result["joined"];
      if (joined is List) ids.addAll(joined.whereType<String>());
      final next = result["next_batch"];
      if (next is! String || next.isEmpty) return ids;
      from = next;
    }
    return ids;
  }

  Set<String> _fromLocalMembers(String userId) {
    final ids = <String>{};
    for (final room in client.matrixClient.rooms) {
      if (room.membership != matrix.Membership.join) continue;
      final member = room.getState(matrix.EventTypes.RoomMember, userId);
      if (member?.content["membership"] == "join") ids.add(room.id);
    }
    return ids;
  }

  @override
  Future<MutualRooms> getMutualRooms(String userId) async {
    Set<String>? ids;
    if (await _serverSupports()) {
      try {
        ids = await _fromServer(userId);
      } catch (e, s) {
        Log.onError(e, s, content: "Mutual rooms request failed");
      }
    }
    ids ??= _fromLocalMembers(userId);

    final dms = client.getComponent<DirectMessagesComponent>();
    final spaces = <Space>[];
    final rooms = <Room>[];
    final counts = <String, int>{};

    for (final id in ids) {
      final space = client.getSpace(id);
      if (space != null) {
        spaces.add(space);
      } else {
        final room = client.getRoom(id);
        if (room == null) continue;
        if (dms != null &&
            dms.isRoomDirectMessage(room) &&
            dms.getDirectMessagePartnerId(room) == userId) continue;
        rooms.add(room);
      }
      final count =
          client.matrixClient.getRoomById(id)?.summary.mJoinedMemberCount;
      if (count != null) counts[id] = count;
    }

    int byName(a, b) =>
        a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    spaces.sort(byName);
    rooms.sort(byName);

    return MutualRooms(spaces: spaces, rooms: rooms, memberCounts: counts);
  }
}
