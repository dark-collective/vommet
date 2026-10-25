import 'package:matrix/matrix.dart' as matrix;

/// Vommet issue 666: the SDK's push rule evaluator, following intentional
/// mentions (MSC3952, Matrix 1.7): when a message has an `m.mentions`
/// property, the legacy rules that look for your display name, user name or
/// "@room" in its text don't apply. The homeserver and Element skip them, so
/// without this Vommet alone notified for messages (often pictures, whose
/// text is the file name) that only happened to contain your name.
class MatrixPushRules {
  static const Set<String> legacyMentionRules = {
    ".m.rule.contains_display_name",
    ".m.rule.contains_user_name",
    ".m.rule.roomnotif",
  };

  static final Expando<({Object? source, matrix.PushruleEvaluator evaluator})>
      _withoutLegacy = Expando();

  /// Whether [content] has an `m.mentions` property, which turns the legacy
  /// mention rules off.
  static bool hasMentions(Map<String, Object?> content) =>
      content.containsKey("m.mentions");

  /// [rules] without the legacy mention rules.
  static matrix.PushRuleSet withoutLegacyMentionRules(
      matrix.PushRuleSet rules) {
    List<matrix.PushRule>? keep(List<matrix.PushRule>? list) =>
        list?.where((r) => !legacyMentionRules.contains(r.ruleId)).toList();

    return matrix.PushRuleSet(
      override: keep(rules.override),
      content: keep(rules.content),
      room: rules.room,
      sender: rules.sender,
      underride: rules.underride,
    );
  }

  /// What the account's push rules say to do for [event].
  static matrix.EvaluatedPushRuleAction match(matrix.Event event) {
    final client = event.room.client;
    if (!hasMentions(event.content)) {
      return client.pushruleEvaluator.match(event);
    }
    return _evaluatorWithoutLegacy(client).match(event);
  }

  static matrix.PushruleEvaluator _evaluatorWithoutLegacy(
      matrix.Client client) {
    // The push rules event is replaced whenever the rules change.
    final source = client.accountData[matrix.EventTypes.PushRules];
    final cached = _withoutLegacy[client];
    if (cached != null && identical(cached.source, source)) {
      return cached.evaluator;
    }

    final rules = client.globalPushRules ?? matrix.PushRuleSet();
    final evaluator =
        matrix.PushruleEvaluator.fromRuleset(withoutLegacyMentionRules(rules));
    _withoutLegacy[client] = (source: source, evaluator: evaluator);
    return evaluator;
  }
}
