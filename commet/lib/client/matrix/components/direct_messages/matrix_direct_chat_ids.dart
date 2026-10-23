import 'package:matrix/matrix.dart' as matrix;

/// Vommet: the ids of all rooms the account's m.direct lists, worked out
/// once per m.direct change instead of per room.
///
/// The SDK's Room.isDirectChat scans every m.direct entry for a room it
/// hasn't seen as a DM, and the home screen asks for every room on each
/// build. A room m.direct doesn't list (and that isn't an invite) can never
/// be a DM to the SDK, so callers can skip it.
class MatrixDirectChatIds {
  static final Expando<_Snapshot> _snapshots = Expando();

  /// False when the SDK's isDirectChat is certainly false for [room]; true
  /// when it has to be asked.
  static bool mayBeDirectChat(matrix.Room room) {
    if (room.membership == matrix.Membership.invite) return true;
    return of(room.client).contains(room.id);
  }

  /// Every room id listed in [client]'s m.direct.
  static Set<String> of(matrix.Client client) {
    // The SDK hands out the same map until m.direct changes.
    final chats = client.directChats;
    final snapshot = _snapshots[client];
    if (snapshot != null && identical(snapshot.source, chats)) {
      return snapshot.roomIds;
    }
    final roomIds = {for (final ids in chats.values) ...ids};
    _snapshots[client] = _Snapshot(chats, roomIds);
    return roomIds;
  }
}

class _Snapshot {
  _Snapshot(this.source, this.roomIds);

  final Map<String, List<String>> source;
  final Set<String> roomIds;
}
