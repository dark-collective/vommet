import 'package:matrix/matrix.dart' as matrix;

/// Vommet issue 667: rooms the server no longer has us in, though no leave
/// ever reached us through sync (a Synapse admin purging the room with the
/// Delete Room API, say). The SDK keeps showing such a room as joined and
/// every send fails, so we check: after a send fails because we aren't in
/// the room, and once per start against `/joined_rooms`.
class MatrixRemovedRooms {
  /// Whether [error] is the server refusing an event because we aren't in
  /// the room. Synapse says "User @x:y not in room !r:z"; Conduit and
  /// Tuwunel say "...not joined..." or "...not a member...".
  static bool isNotInRoomError(Object error) {
    if (error is! matrix.MatrixException) return false;
    if (error.error != matrix.MatrixError.M_FORBIDDEN) return false;
    final message = error.errorMessage.toLowerCase();
    return message.contains("not in room") ||
        message.contains("not in the room") ||
        message.contains("not joined") ||
        message.contains("not a member");
  }

  /// The rooms we think we're in that the server doesn't list as joined.
  static Set<String> notJoined(
          Iterable<String> localJoined, Iterable<String> serverJoined) =>
      localJoined.toSet().difference(serverJoined.toSet());

  /// Servers to rejoin [roomId] through: the room id's own server (rooms
  /// before version 12 carry one), then the servers with the most members
  /// in what we last knew of the room. Our own server is left out: it is
  /// the one that dropped the room, and asking it alone fails again.
  static List<String> viaServers(String roomId, Iterable<String> memberIds,
      {required String? ownServer, int max = 3}) {
    final via = <String>[];
    void add(String? server) {
      if (server == null || server.isEmpty) return;
      if (server == ownServer || via.contains(server)) return;
      via.add(server);
    }

    add(serverOf(roomId));

    final counts = <String, int>{};
    for (final id in memberIds) {
      final server = serverOf(id);
      if (server == null) continue;
      counts[server] = (counts[server] ?? 0) + 1;
    }
    final ranked = counts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });
    for (final entry in ranked) {
      if (via.length >= max) break;
      add(entry.key);
    }
    return via.take(max).toList();
  }

  /// The server part of a Matrix id (`@a:b.org` → `b.org`), or null.
  static String? serverOf(String id) {
    final colon = id.indexOf(":");
    if (colon < 0 || colon == id.length - 1) return null;
    return id.substring(colon + 1);
  }
}
