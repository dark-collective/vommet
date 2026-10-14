import 'dart:async';

import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/client/room.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:commet/utils/notifying_list.dart';
import 'package:commet/utils/notifying_list_filter.dart';
import 'package:matrix/matrix.dart' show Membership;
import 'package:matrix/matrix_api_lite/model/sync_update.dart';

class MatrixDirectMessagesComponent
    extends DirectMessagesComponent<MatrixClient> {
  @override
  MatrixClient client;

  @override
  INotifyingList<Room> directMessageRooms = NotifyingList.empty(growable: true);

  @override
  INotifyingList<Room> highlightedRoomsList =
      NotifyingList.empty(growable: true);

  String currentRoomId = "";

  StreamController _directMessagesChanged = StreamController();

  StreamController _notificationsChanged = StreamController();

  MatrixDirectMessagesComponent(this.client) {
    client.getMatrixClient().onSync.stream.listen(onMatrixSync);
    EventBus.onSelectedRoomChanged.stream
        .listen((value) => currentRoomId = value?.identifier ?? "");

    directMessageRooms = NotifyingListFilter(
      client.rooms,
      where: (item) => isRoomDirectMessage(item),
      onFilterParamsChanged: [_directMessagesChanged.stream],
    );

    highlightedRoomsList = NotifyingListFilter(
      directMessageRooms,
      where: (item) => item.notificationCount > 0,
      onFilterParamsChanged: [_notificationsChanged.stream],
    );
  }

  @override
  bool isRoomDirectMessage(Room room) {
    if (room is! MatrixRoom) {
      return false;
    }

    if (room.matrixRoom.isDirectChat) {
      return true;
    }

    return false;
  }

  @override
  String? getDirectMessagePartnerId(Room room) {
    if (room is! MatrixRoom) {
      return null;
    }

    if (room.matrixRoom.directChatMatrixID != null) {
      return room.matrixRoom.directChatMatrixID;
    }

    return null;
  }

  @override
  String? directMessageCandidate(Room room) {
    if (room is! MatrixRoom) return null;
    final mx = room.matrixRoom;
    if (mx.isSpace) return null;
    final me = mx.client.userID;

    final summary = mx.summary;
    final members =
        (summary.mJoinedMemberCount ?? 0) + (summary.mInvitedMemberCount ?? 0);
    if (members != 2) return null;

    var others =
        (summary.mHeroes ?? const <String>[]).where((id) => id != me).toList();
    if (others.isEmpty) {
      others = mx
          .getParticipants([Membership.join, Membership.invite])
          .map((u) => u.id)
          .where((id) => id != me)
          .toList();
    }
    return others.length == 1 ? others.first : null;
  }

  @override
  Future<void> setDirectMessage(Room room, bool isDirectMessage) async {
    if (room is! MatrixRoom) return;
    if (isDirectMessage) {
      final partner = directMessageCandidate(room);
      if (partner == null) return;
      await room.matrixRoom.addToDirectChat(partner);
    } else {
      await room.matrixRoom.removeFromDirectChat();
    }
  }

  @override
  Future<Room?> createDirectMessage(String userId) async {
    var mx = client.getMatrixClient();
    var roomId = await mx.startDirectChat(userId);

    return client.getRoom(roomId);
  }

  void onMatrixSync(SyncUpdate event) {
    if (event.accountData?.any((e) => e.type == "m.direct") == true) {
      _directMessagesChanged.add(null);
    }

    if (event.rooms?.join?.entries
            .any((e) => e.value.unreadNotifications != null) ==
        true) {
      _notificationsChanged.add(null);
    }
  }
}
