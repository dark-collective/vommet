import 'dart:async';

import 'package:commet/client/matrix/components/direct_messages/matrix_bridged_dm.dart';
import 'package:commet/client/matrix/components/invitation/invite_details.dart';
import 'package:commet/client/matrix/components/invitation/invite_permission_config.dart';
import 'package:commet/client/matrix/extensions/matrix_client_extensions.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/debug/log.dart';
import 'package:matrix/matrix.dart' as matrix;

/// Vommet: a space's rooms as the server lists them for an invitee.
class InviteSpaceChildren {
  const InviteSpaceChildren(this.rooms, {this.complete = true});

  /// (name, room type) of each child room.
  final List<(String name, String? type)> rooms;

  /// False when the server has more pages than we fetched.
  final bool complete;
}

/// Vommet: everything the invite page shows beyond the stripped state, plus
/// the invite blocking settings. Each lookup fails quietly (null): the page
/// then leaves that part out rather than guessing.
class MatrixInvitePreview {
  MatrixInvitePreview(this.client);

  final MatrixClient client;

  matrix.Client get mx => client.matrixClient;

  /// The invite's details from the room's stripped state.
  InviteDetails details(String roomId, {String? fallbackInviterId}) {
    final room = mx.getRoomById(roomId);
    final events = <Map<String, dynamic>>[];
    if (room != null) {
      for (final byKey in room.states.values) {
        for (final e in byKey.values) {
          events.add({
            "type": e.type,
            "state_key": e.stateKey,
            "sender": e.senderId,
            "content": e.content,
          });
        }
      }
    }
    return InviteDetails.fromStrippedState(roomId, mx.userID ?? "", events,
        fallbackInviterId: fallbackInviterId);
  }

  /// The joined member count, if the server will tell an invitee
  /// (room summary; for a space, also the hierarchy's first entry).
  Future<int?> memberCount(InviteDetails details) async {
    try {
      final via = details.inviterServer;
      final preview = await mx.getRoomPreview(details.roomId,
          via: via == null ? null : [via]);
      if (preview?.numMembers != null) return preview!.numMembers;
    } catch (e) {
      Log.i("Invite preview: no room summary for ${details.roomId}: $e");
    }
    return null;
  }

  /// A space's rooms, if the server lists them for an invitee. The first
  /// value is the space's own member count from the same answer.
  Future<(InviteSpaceChildren?, int?)> spaceChildren(String roomId) async {
    try {
      final response =
          await mx.getSpaceHierarchy(roomId, maxDepth: 1, limit: 50);
      int? members;
      final rooms = <(String, String?)>[];
      for (final chunk in response.rooms) {
        if (chunk.roomId == roomId) {
          members = chunk.numJoinedMembers;
          continue;
        }
        final name = chunk.name ?? chunk.canonicalAlias;
        if (name == null || name.trim().isEmpty) continue;
        rooms.add((name, chunk.roomType));
      }
      return (
        InviteSpaceChildren(rooms, complete: response.nextBatch == null),
        members
      );
    } catch (e) {
      Log.i("Invite preview: no hierarchy for $roomId: $e");
      return (null, null);
    }
  }

  static const _mutualFeature = "uk.half-shot.msc2666.query_mutual_rooms";
  static const _mutualPath =
      "/client/unstable/uk.half-shot.msc2666/user/mutual_rooms";

  /// Names of the joined rooms you share with [userId] (MSC2666 when the
  /// server has it, else the member lists we have). Null if unknown.
  Future<List<String>?> sharedRoomNames(String userId,
      {String? excludeRoomId}) async {
    Set<String>? ids;
    try {
      final versions = await mx.getVersions();
      final features = versions.unstableFeatures ?? const {};
      if (features[_mutualFeature] == true ||
          features["$_mutualFeature.stable"] == true) {
        ids = {};
        String? from;
        for (var page = 0; page < 10; page++) {
          final result = await mx.request(matrix.RequestType.GET, _mutualPath,
              query: {"user_id": userId, if (from != null) "from": from});
          final joined = result["joined"];
          if (joined is List) ids.addAll(joined.whereType<String>());
          final next = result["next_batch"];
          if (next is! String || next.isEmpty) break;
          from = next;
        }
      }
    } catch (e) {
      Log.i("Invite preview: mutual rooms request failed: $e");
      ids = null;
    }

    ids ??= {
      for (final room in mx.rooms)
        if (room.membership == matrix.Membership.join &&
            room
                    .getState(matrix.EventTypes.RoomMember, userId)
                    ?.content["membership"] ==
                "join")
          room.id
    };

    final names = <String>[];
    for (final id in ids) {
      if (id == excludeRoomId) continue;
      final room = mx.getRoomById(id);
      if (room == null || room.membership != matrix.Membership.join) continue;
      // Your DM with them isn't a "room you share".
      if (MatrixBridgedDm.partner(room) == userId) continue;
      names.add(room.getLocalizedDisplayname());
    }
    names.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return names;
  }

  /// Your other direct chats with [userId]: (any, any still joined).
  (bool, bool) directChatsWith(String userId, {String? excludeRoomId}) {
    final Object? ids = mx.directChats[userId];
    if (ids is! List) return (false, false);
    final others = ids.whereType<String>().where((id) => id != excludeRoomId);
    final joined = others
        .any((id) => mx.getRoomById(id)?.membership == matrix.Membership.join);
    return (others.isNotEmpty, joined);
  }

  /// Whether you've verified [userId].
  bool isVerified(String userId) =>
      mx.userDeviceKeys[userId]?.verified == matrix.UserVerifiedStatus.verified;

  /// Your homeserver's name (for "Sends the room to nether.im's admins").
  String get ownServer =>
      InvitePermissionConfig.serverOf(mx.userID) ?? mx.homeserver?.host ?? "";

  /// Reports the room to your server's admins (spec: POST
  /// /rooms/{roomId}/report). Throws when the server refuses, e.g. a
  /// remote room nobody on your server has joined.
  Future<void> reportRoom(String roomId, String reason) async {
    await mx.request(matrix.RequestType.POST,
        "/client/v3/rooms/${Uri.encodeComponent(roomId)}/report",
        data: {"reason": reason});
  }

  // ---------------------------------------------------------------- blocking

  Map<String, dynamic>? _content(String type) {
    final c = mx.accountData[type]?.content;
    return c == null ? null : Map<String, dynamic>.from(c);
  }

  InvitePermissionConfig get config => InvitePermissionConfig(
        stable: _content(InvitePermissionConfig.stableType),
        blanket: _content(InvitePermissionConfig.blanketType),
        lists: _content(InvitePermissionConfig.listsType),
      );

  static const Set<String> configTypes = {
    InvitePermissionConfig.stableType,
    InvitePermissionConfig.blanketType,
    InvitePermissionConfig.listsType,
  };

  Future<void> _write(String type, Map<String, dynamic> content) async {
    await mx.setAccountData(mx.userID!, type, content);
    // Don't wait for the sync echo.
    mx.accountData[type] = matrix.BasicEvent(type: type, content: content);
  }

  Future<void> setBlocksAll(bool block) async {
    for (final write in config.setBlocksAll(block).entries) {
      await _write(write.key, write.value);
    }
  }

  List<String> get blockedServers => config.blockedServers;

  Future<void> blockServer(String server) async {
    final content = config.withBlockedServer(server);
    if (content != null) {
      await _write(InvitePermissionConfig.listsType, content);
    }
  }

  Future<void> unblockServer(String server) async {
    final content = config.withoutBlockedServer(server);
    if (content != null) {
      await _write(InvitePermissionConfig.listsType, content);
    }
  }

  /// Fires when any invite permission slot changes (here or elsewhere).
  Stream<void> get onConfigChanged => mx.onSync.stream
      .where((u) =>
          u.accountData?.any((e) => configTypes.contains(e.type)) == true)
      .map((_) {});
}
