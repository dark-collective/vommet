import 'package:commet/client/matrix/components/direct_messages/matrix_bridged_dm.dart';
import 'dart:async';

import 'package:commet/client/matrix/components/direct_messages/matrix_direct_chat_ids.dart';
import 'package:commet/utils/dm_shape.dart';
import 'package:matrix/matrix.dart' as matrix;

/// Vommet: a Matrix room's [DmShape] from m.direct and its joined and invited
/// members ("New room info page" experiment).
class MatrixDmShape {
  static DmShape of(matrix.Room room) {
    final inMDirect =
        MatrixDirectChatIds.mayBeDirectChat(room) && room.isDirectChat;
    if (!inMDirect) return DmShape.room;
    final me = room.client.userID ?? "";
    final partner = MatrixBridgedDm.partner(room);
    final bots = MatrixBridgedDm.bots(room);
    final membership = partner == null
        ? null
        : room
            .getState(matrix.EventTypes.RoomMember, partner)
            ?.content["membership"];
    return DmShape.decide(
      inMDirect: true,
      activeMemberIds: room
          .getParticipants([matrix.Membership.join, matrix.Membership.invite])
          .map((u) => u.id)
          .where((id) => !bots.contains(id)),
      ownId: me,
      partnerId: partner,
      partnerMembership: membership is String ? membership : null,
      activeMemberCount: MatrixBridgedDm.activeCount(room, bots),
    );
  }

  /// The other active members' names for an unnamed group ("Juniper and
  /// Kit"): the room summary's heroes, else the members known locally.
  static String groupName(matrix.Room room) {
    final me = room.client.userID;
    final bots = MatrixBridgedDm.bots(room);
    final active = {
      for (final u in room
          .getParticipants([matrix.Membership.join, matrix.Membership.invite]))
        if (!bots.contains(u.id)) u.id: u
    };
    var ids = (room.summary.mHeroes ?? const <String>[])
        .where((id) => id.isNotEmpty && id != me && !bots.contains(id))
        .toList();
    if (ids.isEmpty) ids = active.keys.where((id) => id != me).toList();
    final names = [
      for (final id in ids)
        room.unsafeGetUserFromMemoryOrFallback(id).calcDisplayname()
    ];
    final count = MatrixBridgedDm.activeCount(room, bots) ?? 0;
    final others = count > 0 ? count - 1 : active.length - 1;
    return dmGroupName(names, total: others);
  }

  static final Expando<Stream<void>> _changes = Expando();

  /// Fires after a sync that changed the account's m.direct. One listener
  /// on the client's syncs, shared by every room.
  static Stream<void> directChatsChanged(matrix.Client client) {
    if (_changes[client] case final stream?) return stream;
    final controller = StreamController<void>.broadcast();
    client.onSync.stream.listen((sync) {
      if (sync.accountData?.any((e) => e.type == "m.direct") == true) {
        controller.add(null);
      }
    });
    return _changes[client] = controller.stream;
  }
}
