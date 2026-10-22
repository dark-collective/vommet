import 'package:commet/client/room.dart';
import 'package:commet/debug/log.dart';
import 'package:matrix/matrix.dart' as matrix;

/// Vommet: applies the user's default notification level (Settings >
/// Notifications > New rooms) to rooms the account has just joined.
///
/// A room counts as newly joined when a sync carries our own
/// `m.room.member` join whose previous membership was not `join`, and the
/// join is recent (so rooms found in an initial sync after a fresh login, or
/// after a long time offline, are left alone).
class MatrixDefaultPushRule {
  static const Duration maxJoinAge = Duration(hours: 1);

  /// Rooms already handled in this session, so a join seen twice (for
  /// example in a timeline and in state) is applied once.
  final Set<String> _handled = {};

  /// Returns the ids of rooms in [update] that [userId] newly joined, mapped
  /// to whether the invite or join marked the room as a direct chat.
  static Map<String, bool> findNewlyJoinedRooms(
      matrix.SyncUpdate update, String userId, DateTime now) {
    final result = <String, bool>{};
    final joins = update.rooms?.join;
    if (joins == null) return result;

    for (final entry in joins.entries) {
      final events = [
        ...?entry.value.state,
        ...?entry.value.timeline?.events,
      ];

      for (final event in events) {
        if (event.type != matrix.EventTypes.RoomMember) continue;
        if (event.stateKey != userId) continue;
        if (event.content['membership'] != 'join') continue;
        if (now.difference(event.originServerTs) > maxJoinAge) continue;

        final prev = event.prevContent ??
            (event.unsigned?['prev_content'] as Map<String, Object?>?);
        if (prev?['membership'] == 'join') continue;

        final isDirect =
            prev?['is_direct'] == true || event.content['is_direct'] == true;
        result[entry.key] = (result[entry.key] ?? false) || isDirect;
      }
    }

    return result;
  }

  /// Preference value meaning "leave new rooms at the account's default".
  static const String accountDefault = "default";

  /// The level a preference value names, or null for [accountDefault] (and
  /// anything unknown).
  static PushRule? parse(String value) {
    for (final rule in PushRule.values) {
      if (rule.name == value) return rule;
    }
    return null;
  }

  static matrix.PushRuleState toMatrix(PushRule rule) {
    switch (rule) {
      case PushRule.notify:
        return matrix.PushRuleState.notify;
      case PushRule.mentionsOnly:
        return matrix.PushRuleState.mentionsOnly;
      case PushRule.dontNotify:
        return matrix.PushRuleState.dontNotify;
    }
  }

  /// Whether the account has a rule of its own for [room] (a mute or a room
  /// rule), as opposed to the room following the account's defaults.
  static bool hasOwnRule(matrix.Room room) {
    final rules = room.client.globalPushRules;
    return rules?.override?.any((r) => r.ruleId == room.id) == true ||
        rules?.room?.any((r) => r.ruleId == room.id) == true;
  }

  /// Applies [roomDefault] or [directDefault] (null = leave at the account's
  /// default) to rooms newly joined in [update]. Rooms that already have
  /// their own rule, spaces, and rooms the user created are left alone.
  Future<void> onSync(matrix.Client client, matrix.SyncUpdate update,
      {required PushRule? roomDefault,
      required PushRule? directDefault,
      required Future<void> Function(matrix.Room room, PushRule rule)
          apply}) async {
    if (roomDefault == null && directDefault == null) return;

    final userId = client.userID;
    if (userId == null) return;

    final joined = findNewlyJoinedRooms(update, userId, DateTime.now());
    for (final entry in joined.entries) {
      if (!_handled.add(entry.key)) continue;

      final room = client.getRoomById(entry.key);
      if (room == null || room.isSpace) continue;

      final creator = room.getState(matrix.EventTypes.RoomCreate)?.senderId;
      if (creator == userId) continue;

      if (hasOwnRule(room)) continue;

      final isDirect = entry.value || room.isDirectChat;
      final rule = isDirect ? directDefault : roomDefault;
      if (rule == null) continue;

      try {
        await apply(room, rule);
        Log.i("Applied default notification level ${rule.name} "
            "to newly joined ${isDirect ? "direct chat" : "room"} ${room.id}");
      } catch (e, s) {
        Log.onError(e, s,
            content: "Failed to apply default notification level");
      }
    }
  }
}
