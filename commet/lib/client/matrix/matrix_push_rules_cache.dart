import 'package:commet/client/matrix/matrix_push_rules.dart';
import 'package:matrix/matrix.dart' as matrix;

/// Vommet: the account's push rules, parsed once per push rules account-data
/// event and shared by every room, with one evaluator. Each room used to
/// parse the rules and build its own evaluator to work out its default
/// notification setting, about 8% of startup on a slow device.
class MatrixPushRulesCache {
  MatrixPushRulesCache._(this._content, this.rules);

  static final _cache = Expando<MatrixPushRulesCache>();

  final Map<String, Object?> _content;

  /// The same rules as `client.globalPushRules`.
  final matrix.PushRuleSet rules;

  /// Vommet issue 745: counts each room's members as the homeserver does.
  late final RoomPushRules evaluator = RoomPushRules(rules);

  /// Rule ids a room's own setting can drop when its default is worked out:
  /// every override rule, and the room rules that don't notify.
  late final Set<String> _ownRuleIds = {
    for (final r in rules.override ?? const <matrix.PushRule>[]) r.ruleId,
    for (final r in rules.room ?? const <matrix.PushRule>[])
      if (!r.actions.contains("notify")) r.ruleId,
  };

  /// The rules for [client], or null without push rules (as
  /// `client.globalPushRules`). A new push rules event (a change in sync)
  /// gets a new entry.
  static MatrixPushRulesCache? of(matrix.Client client) {
    final event = client.accountData["m.push_rules"];
    if (event == null) return null;
    final cached = _cache[event];
    if (cached != null && identical(cached._content, event.content)) {
      return cached;
    }
    final rules = client.globalPushRules;
    if (rules == null) return null;
    return _cache[event] = MatrixPushRulesCache._(event.content, rules);
  }

  /// Whether [roomId] has a rule the room's default setting leaves out.
  bool hasOwnRule(String roomId) => _ownRuleIds.contains(roomId);
}
