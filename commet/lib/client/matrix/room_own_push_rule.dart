// Vommet: a room's own notification rule, as set on its settings page. The
// page offers "Use default (…)", which removes the room's own rules so it
// follows the account's defaults, and the explicit levels, which always
// write a rule for the room so it keeps that level when the defaults change.

import 'package:commet/client/matrix/matrix_push_rules.dart';
import 'package:commet/client/room.dart';
import 'package:matrix/matrix.dart' as matrix;

typedef DeletePushRule = Future<void> Function(
    matrix.PushRuleKind kind, String ruleId);

typedef PutPushRule = Future<void> Function(
    matrix.PushRuleKind kind, String ruleId, List<Object> actions,
    {List<matrix.PushCondition>? conditions});

class RoomOwnPushRule {
  /// Whether [rules] hold a rule of [roomId]'s own: an override rule (mute)
  /// or a room rule (mentions only, or an explicit "notify").
  static bool hasOwnRule(matrix.PushRuleSet? rules, String roomId) =>
      rules?.override?.any((r) => r.ruleId == roomId) == true ||
      rules?.room?.any((r) => r.ruleId == roomId) == true;

  /// [rules] without [roomId]'s own rules: what the room follows by default.
  static matrix.PushRuleSet withoutOwnRules(
          matrix.PushRuleSet rules, String roomId) =>
      matrix.PushRuleSet(
        override: rules.override?.where((r) => r.ruleId != roomId).toList(),
        content: rules.content,
        room: rules.room?.where((r) => r.ruleId != roomId).toList(),
        sender: rules.sender,
        underride: rules.underride,
      );

  /// The level the account's defaults give [room] without a rule of its
  /// own: All Messages when an ordinary message notifies, else Mentions &
  /// Keywords. [probe] is an ordinary message from someone else in [room].
  static PushRule defaultLevel(matrix.PushRuleSet? rules, matrix.Event probe) {
    if (rules == null) return PushRule.notify;
    final set = withoutOwnRules(rules, probe.room.id);
    return RoomPushRules(set).match(probe).notify
        ? PushRule.notify
        : PushRule.mentionsOnly;
  }

  /// Removes [roomId]'s own rules from [rules] (those that exist).
  static Future<void> clear(matrix.PushRuleSet? rules, String roomId,
      {required DeletePushRule delete}) async {
    if (rules?.override?.any((r) => r.ruleId == roomId) == true) {
      await delete(matrix.PushRuleKind.override, roomId);
    }
    if (rules?.room?.any((r) => r.ruleId == roomId) == true) {
      await delete(matrix.PushRuleKind.room, roomId);
    }
  }

  /// Writes [level] as [roomId]'s own rule, replacing its other own rule:
  /// All Messages = a room rule that notifies, Mentions & Keywords = a room
  /// rule without actions, Mute = an override rule without actions (the
  /// same rules Element and the SDK write).
  static Future<void> set(
      matrix.PushRuleSet? rules, String roomId, PushRule level,
      {required DeletePushRule delete, required PutPushRule put}) async {
    final hasOverride = rules?.override?.any((r) => r.ruleId == roomId) == true;
    final hasRoom = rules?.room?.any((r) => r.ruleId == roomId) == true;
    switch (level) {
      case PushRule.notify:
      case PushRule.mentionsOnly:
        if (hasOverride) await delete(matrix.PushRuleKind.override, roomId);
        await put(matrix.PushRuleKind.room, roomId,
            level == PushRule.notify ? ["notify"] : []);
        break;
      case PushRule.dontNotify:
        if (hasRoom) await delete(matrix.PushRuleKind.room, roomId);
        await put(matrix.PushRuleKind.override, roomId, [], conditions: [
          matrix.PushCondition(
            kind: matrix.PushRuleConditions.eventMatch.name,
            key: 'room_id',
            pattern: roomId,
          ),
        ]);
        break;
    }
  }
}
