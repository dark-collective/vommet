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

  /// Vommet issue 631: the level set on a joined space that has [room] as a
  /// child, or null when none of its spaces has a level of its own.
  static PushRule? spaceLevelFor(matrix.Room room) {
    final levels = <PushRule>[];
    for (final space in room.client.rooms) {
      if (!space.isSpace || space.membership != matrix.Membership.join) {
        continue;
      }
      if (!space.spaceChildren.any((c) => c.roomId == room.id)) continue;
      if (!hasOwnRule(space)) continue;
      levels.add(fromMatrix(space.pushRuleState));
    }
    return inheritedLevel(levels);
  }

  /// Of the levels of a room's spaces, the loudest wins, so being in a muted
  /// space never silences a room another of your spaces wants to hear.
  static PushRule? inheritedLevel(Iterable<PushRule> levels) {
    PushRule? result;
    for (final level in levels) {
      if (result == null || _loudness(level) > _loudness(result)) {
        result = level;
      }
    }
    return result;
  }

  static int _loudness(PushRule rule) {
    switch (rule) {
      case PushRule.notify:
        return 2;
      case PushRule.mentionsOnly:
        return 1;
      case PushRule.dontNotify:
        return 0;
    }
  }

  static PushRule fromMatrix(matrix.PushRuleState state) {
    switch (state) {
      case matrix.PushRuleState.notify:
        return PushRule.notify;
      case matrix.PushRuleState.mentionsOnly:
        return PushRule.mentionsOnly;
      case matrix.PushRuleState.dontNotify:
        return PushRule.dontNotify;
    }
  }

  /// Applies the level of the room's space (see [spaceLevelFor]), else
  /// [roomDefault] or [directDefault] (null = leave at the account's
  /// default), to rooms newly joined in [update]. Rooms that already have
  /// their own rule, spaces, and rooms the user created are left alone.
  Future<void> onSync(matrix.Client client, matrix.SyncUpdate update,
      {required PushRule? roomDefault,
      required PushRule? directDefault,
      required Future<void> Function(matrix.Room room, PushRule rule)
          apply}) async {
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
      // Vommet issue 631: a room joined in a space follows the level chosen
      // for the space (Discord-style), before the "Rooms you join" default.
      final rule =
          isDirect ? directDefault : (spaceLevelFor(room) ?? roomDefault);
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
