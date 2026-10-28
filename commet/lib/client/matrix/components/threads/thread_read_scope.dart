import 'package:commet/main.dart';
import 'package:matrix/matrix.dart' as matrix;

/// Vommet issues 804 and 805: which threads keep their own read state
/// ("Read state per thread"). [mine] = threads you started or replied in,
/// the same threads the Threads list's "Mine" filter shows.
enum ThreadReadScope { off, mine, all }

/// The account's choice (Settings › Notifications › Threads), with
/// overrides per space and per room, saved in account data so it follows
/// you to every device. A room's own choice wins, then its spaces' (the one
/// tracking the most threads, like notification levels), then the account
/// default.
class ThreadReadScopes {
  static const String type = "im.vommet.thread_read_state";

  static ThreadReadScope? parse(Object? value) {
    for (final scope in ThreadReadScope.values) {
      if (scope.name == value) return scope;
    }
    return null;
  }

  static Map<String, Object?> _content(matrix.Client client) =>
      client.accountData[type]?.content ?? const {};

  static Map<String, Object?> _rooms(matrix.Client client) {
    final rooms = _content(client)["rooms"];
    return rooms is Map<String, Object?> ? rooms : const {};
  }

  /// The account default. Until one is saved, the old "Read state per
  /// thread" experiment switch on this device decides (on = all threads).
  static ThreadReadScope accountDefault(matrix.Client client) =>
      parse(_content(client)["default"]) ??
      (preferences.experimentThreadReadState.value
          ? ThreadReadScope.all
          : ThreadReadScope.off);

  /// The room's (or space's) own choice, or null when it follows the
  /// default.
  static ThreadReadScope? ownScope(matrix.Room room) =>
      parse(_rooms(room.client)[room.id]);

  /// The choice of the joined spaces that have [room] as a child, or null
  /// when none has its own.
  static ThreadReadScope? spaceScopeFor(matrix.Room room) {
    final scopes = <ThreadReadScope>[];
    for (final space in room.client.rooms) {
      if (!space.isSpace || space.membership != matrix.Membership.join) {
        continue;
      }
      if (!space.spaceChildren.any((c) => c.roomId == room.id)) continue;
      final own = ownScope(space);
      if (own != null) scopes.add(own);
    }
    return widest(scopes);
  }

  /// Of several choices, the one tracking the most threads.
  static ThreadReadScope? widest(Iterable<ThreadReadScope> scopes) {
    ThreadReadScope? result;
    for (final scope in scopes) {
      if (result == null || scope.index > result.index) result = scope;
    }
    return result;
  }

  /// What a room follows when it has no choice of its own.
  static ThreadReadScope defaultFor(matrix.Room room) =>
      (room.isSpace ? null : spaceScopeFor(room)) ??
      accountDefault(room.client);

  static ThreadReadScope scopeFor(matrix.Room room) =>
      ownScope(room) ?? defaultFor(room);

  static Future<void> setAccountDefault(
          matrix.Client client, ThreadReadScope scope) =>
      _write(client, {..._content(client), "default": scope.name});

  /// Sets the room's (or space's) own choice; null follows the default.
  static Future<void> setOwnScope(matrix.Room room, ThreadReadScope? scope) {
    final rooms = {..._rooms(room.client)};
    if (scope == null) {
      rooms.remove(room.id);
    } else {
      rooms[room.id] = scope.name;
    }
    return _write(room.client, {..._content(room.client), "rooms": rooms});
  }

  static Future<void> _write(
      matrix.Client client, Map<String, Object?> content) async {
    final userId = client.userID;
    if (userId == null) return;
    await client.setAccountData(userId, type, content);
    client.accountData[type] = matrix.BasicEvent(type: type, content: content);
  }

  /// Whether [root] is a thread you started, or one the server says you
  /// took part in (its bundled `current_user_participated`).
  static bool startedOrParticipated(matrix.Event root) {
    if (root.senderId == root.room.client.userID) return true;
    final relations = root.unsigned?["m.relations"];
    if (relations is! Map) return false;
    final thread = relations[matrix.RelationshipTypes.thread];
    return thread is Map && thread["current_user_participated"] == true;
  }
}
