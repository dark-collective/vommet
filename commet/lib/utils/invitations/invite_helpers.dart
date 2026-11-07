import 'package:commet/client/client.dart';
import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:matrix/matrix.dart' as matrix;

/// Whether we've never shared a direct message or a joined room with
/// [userId] (as far as this device knows).
bool isFirstContact(Client client, String userId) {
  final dms = client.getComponent<DirectMessagesComponent>();
  if (dms != null &&
      dms.directMessageRooms
          .any((r) => dms.getDirectMessagePartnerId(r) == userId)) {
    return false;
  }
  for (final room in client.rooms) {
    if (room is! MatrixRoom) continue;
    final membership = room.matrixRoom
        .getState(matrix.EventTypes.RoomMember, userId)
        ?.content
        .tryGet<String>("membership");
    if (membership == "join") return false;
  }
  return true;
}

/// The plain invite API call: the SDK's Client.inviteUser also sends the
/// room's history keys, so go around it when they're kept back.
Future<void> inviteWithoutHistory(
    MatrixClient client, String roomId, String userId) {
  final mx = client.getMatrixClient();
  return matrix.MatrixApi(
          homeserver: mx.homeserver,
          accessToken: mx.accessToken,
          httpClient: mx.httpClient)
      .inviteUser(roomId, userId);
}
