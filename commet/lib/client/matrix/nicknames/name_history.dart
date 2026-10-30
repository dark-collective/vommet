// Vommet: identity per place, moderator view (rule R7). A moderator sees who
// someone is behind the name they show in a room: their global name, their
// Matrix ID and the names they used in the room before, read from their
// m.room.member events.
import 'dart:convert';

import 'package:matrix/matrix.dart' as matrix;

/// One name someone showed in a room, from [time] on. [name] is null when
/// they showed no name (Matrix apps then show the Matrix ID).
class NameChange {
  final DateTime time;
  final String? name;

  const NameChange(this.time, this.name);
}

/// Who someone is behind the name they show in one room.
class NameHistory {
  final String userId;
  final String? globalName;
  final String? roomName;

  /// Newest first.
  final List<NameChange> changes;

  const NameHistory(this.userId, this.globalName, this.roomName, this.changes);

  /// How many member events are read at most.
  static const int limit = 100;

  /// The names [userId] used in their member events, newest first, one
  /// entry per change (joins and leaves that keep the name are left out).
  static List<NameChange> changesFrom(
      Iterable<matrix.MatrixEvent> events, String userId) {
    final sorted = events
        .where((e) =>
            e.type == matrix.EventTypes.RoomMember &&
            e.stateKey == userId &&
            e.content["membership"] == "join")
        .toList()
      ..sort((a, b) => a.originServerTs.compareTo(b.originServerTs));
    final result = <NameChange>[];
    for (final e in sorted) {
      final raw = e.content["displayname"];
      final name = raw is String && raw.trim().isNotEmpty ? raw : null;
      if (result.isNotEmpty && result.last.name == name) continue;
      result.add(NameChange(e.originServerTs, name));
    }
    return result.reversed.toList();
  }

  /// Reads [userId]'s global name and their recent name changes in [room].
  static Future<NameHistory> load(matrix.Room room, String userId) async {
    final client = room.client;
    String? globalName;
    try {
      globalName =
          (await client.getUserProfile(userId, maxCacheAge: Duration.zero))
              .displayname;
    } catch (_) {
      // A profile the server won't share; the rest still helps.
    }
    final events = await client.getRoomEvents(room.id, matrix.Direction.b,
        limit: limit,
        filter: jsonEncode({
          "types": [matrix.EventTypes.RoomMember],
          "senders": [userId],
        }));
    final member = room.unsafeGetUserFromMemoryOrFallback(userId);
    return NameHistory(userId, globalName, member.displayName,
        changesFrom(events.chunk, userId));
  }
}
