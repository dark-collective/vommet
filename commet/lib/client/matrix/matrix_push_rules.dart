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

  static final Expando<
          ({Object? source, RoomPushRules all, RoomPushRules withoutLegacy})>
      _rules = Expando();

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
    final rules = _rulesOf(event.room.client);
    return hasMentions(event.content)
        ? rules.withoutLegacy.match(event)
        : rules.all.match(event);
  }

  static ({Object? source, RoomPushRules all, RoomPushRules withoutLegacy})
      _rulesOf(matrix.Client client) {
    // The push rules event is replaced whenever the rules change.
    final source = client.accountData[matrix.EventTypes.PushRules];
    final cached = _rules[client];
    if (cached != null && identical(cached.source, source)) return cached;

    final rules = client.globalPushRules ?? matrix.PushRuleSet();
    return _rules[client] = (
      source: source,
      all: RoomPushRules(rules),
      withoutLegacy: RoomPushRules(withoutLegacyMentionRules(rules)),
    );
  }

  /// Vommet issue 745: how many people have joined [room], as the homeserver
  /// counts them for `room_member_count`: the room summary's count. The SDK
  /// counts only the members loaded on this device, so a direct message
  /// whose members weren't loaded (often after catching up on messages
  /// received while offline) didn't look like a one-to-one chat.
  static int joinedMemberCount(matrix.Room room) {
    final summary = room.summary.mJoinedMemberCount;
    if (summary != null && summary > 0) return summary;
    return room.getParticipants([matrix.Membership.join]).length;
  }

  static final _memberCountCondition = RegExp(r"^(==|<=|>=|<|>)?([0-9]+)$");

  /// Whether a `room_member_count` condition's [condition] (e.g. "2" or
  /// ">=3") holds for [count] members. Null when it can't be read.
  static bool? memberCountMatches(String? condition, int count) {
    final match = _memberCountCondition.firstMatch(condition ?? "");
    if (match == null) return null;
    final n = int.parse(match.group(2)!);
    return switch (match.group(1)) {
      "<" => count < n,
      ">" => count > n,
      "<=" => count <= n,
      ">=" => count >= n,
      _ => count == n,
    };
  }

  /// [rules] for a room of [count] joined members: their
  /// `room_member_count` conditions are decided here, so the SDK's
  /// evaluator never counts members itself. A rule whose condition holds
  /// loses it, one whose condition fails is left out.
  static matrix.PushRuleSet forMemberCount(
      matrix.PushRuleSet rules, int count) {
    List<matrix.PushRule>? decide(List<matrix.PushRule>? list) => list
        ?.map((rule) {
          final conditions = rule.conditions;
          if (conditions == null) return rule;
          final kept = <matrix.PushCondition>[];
          for (final c in conditions) {
            final holds = c.kind == "room_member_count"
                ? memberCountMatches(c.is$, count)
                : null;
            if (holds == false) return null;
            if (holds == null) kept.add(c);
          }
          if (kept.length == conditions.length) return rule;
          return matrix.PushRule(
            actions: rule.actions,
            conditions: kept,
            default$: rule.default$,
            enabled: rule.enabled,
            pattern: rule.pattern,
            ruleId: rule.ruleId,
          );
        })
        .nonNulls
        .toList();

    return matrix.PushRuleSet(
      override: decide(rules.override),
      content: decide(rules.content),
      room: decide(rules.room),
      sender: decide(rules.sender),
      underride: decide(rules.underride),
    );
  }
}

/// Vommet issue 745: a push rule evaluator that counts a room's members as
/// the homeserver does ([MatrixPushRules.joinedMemberCount]), with one SDK
/// evaluator per member count.
class RoomPushRules {
  RoomPushRules(this.rules);

  final matrix.PushRuleSet rules;

  final Map<int, matrix.PushruleEvaluator> _byMemberCount = {};

  /// What [rules] say to do for [event].
  matrix.EvaluatedPushRuleAction match(matrix.Event event) {
    final count = MatrixPushRules.joinedMemberCount(event.room);
    final evaluator = _byMemberCount[count] ??=
        matrix.PushruleEvaluator.fromRuleset(
            MatrixPushRules.forMemberCount(rules, count));
    return evaluator.match(event);
  }
}
