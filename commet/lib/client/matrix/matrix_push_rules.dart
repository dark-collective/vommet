import 'package:commet/client/matrix/components/threads/thread_reply_rules.dart';
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

  static final Expando<
          ({Object? source, Map<String, (RoomPushRules, RoomPushRules)> rooms})>
      _unmuted = Expando();

  /// Discord's rule: a muted room still shows mentions. What the rules say
  /// for [event] without its room's own rules (the mute override).
  static matrix.EvaluatedPushRuleAction matchUnmuted(matrix.Event event) {
    final client = event.room.client;
    final source = client.accountData[matrix.EventTypes.PushRules];
    var cached = _unmuted[client];
    if (cached == null || !identical(cached.source, source)) {
      cached = _unmuted[client] = (source: source, rooms: {});
    }
    final id = event.room.id;
    final (all, withoutLegacy) = cached.rooms.putIfAbsent(id, () {
      final rules = client.globalPushRules ?? matrix.PushRuleSet();
      final own = matrix.PushRuleSet(
        override: rules.override?.where((r) => r.ruleId != id).toList(),
        content: rules.content,
        room: rules.room?.where((r) => r.ruleId != id).toList(),
        sender: rules.sender,
        underride: rules.underride,
      );
      return (
        RoomPushRules(own),
        RoomPushRules(withoutLegacyMentionRules(own))
      );
    });
    return hasMentions(event.content)
        ? withoutLegacy.match(event)
        : all.match(event);
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

  /// Vommet issue 918: whether [rule] says "notify" without saying how
  /// loud: a room's own "All Messages" rule (written by the room's settings
  /// page, which offers no sound choice) or a "Threads I'm in" rule. Its
  /// sound comes from the account's Off/On/Noisy grid instead, see
  /// [withoutLoudnessNeutralRules].
  static bool isLoudnessNeutral(
      matrix.PushRuleKind kind, matrix.PushRule rule) {
    final ours = switch (kind) {
      matrix.PushRuleKind.room => true,
      matrix.PushRuleKind.underride => _isThreadReplyRule(rule),
      _ => false,
    };
    return ours &&
        rule.actions.contains("notify") &&
        !rule.actions.any((a) => a is Map && a["set_tweak"] == "sound");
  }

  /// Vommet issue 918: [rules] without the loudness-neutral rules (and the
  /// other thread reply rules, which only decide whether a thread reply
  /// notifies), or null when there are none. What these rules give an event
  /// is how loud the account's grid makes it.
  static matrix.PushRuleSet? withoutLoudnessNeutralRules(
      matrix.PushRuleSet rules) {
    final neutral = [
      for (final r in rules.room ?? const <matrix.PushRule>[])
        if (isLoudnessNeutral(matrix.PushRuleKind.room, r)) r,
      for (final r in rules.underride ?? const <matrix.PushRule>[])
        if (isLoudnessNeutral(matrix.PushRuleKind.underride, r)) r,
    ];
    if (neutral.isEmpty) return null;
    return matrix.PushRuleSet(
      override: rules.override,
      content: rules.content,
      room: [
        for (final r in rules.room ?? const <matrix.PushRule>[])
          if (!neutral.contains(r)) r,
      ],
      sender: rules.sender,
      underride: [
        for (final r in rules.underride ?? const <matrix.PushRule>[])
          if (!_isThreadReplyRule(r)) r,
      ],
    );
  }

  /// Vommet issue 918: the grid's plain message rows and the encrypted rows
  /// that list the same messages in an encrypted room.
  static const encryptedRows = {
    ".m.rule.message": ".m.rule.encrypted",
    ".m.rule.room_one_to_one": ".m.rule.encrypted_room_one_to_one",
  };

  /// Vommet issue 918: [rules] for a message in an encrypted room. The
  /// device checks it once decrypted, so it matches the plain rows ("Group
  /// chats", "One-to-one chats"), not the "Encrypted …" rows the grid (and
  /// the room's badge) show for it; with only those at Noisy it notified
  /// silently. A plain row's rule that notifies without a sound takes the
  /// sound of its encrypted row when that row has one. Nothing gets quieter
  /// and whether it notifies or highlights doesn't change. Null when
  /// nothing changes.
  static matrix.PushRuleSet? withEncryptedRowsSound(matrix.PushRuleSet rules) {
    bool isSound(Object? a) => a is Map && a["set_tweak"] == "sound";
    final underride = [...?rules.underride];
    var changed = false;
    for (var i = 0; i < underride.length; i++) {
      final plain = underride[i];
      final encryptedId = encryptedRows[plain.ruleId];
      if (encryptedId == null ||
          !plain.enabled ||
          !plain.actions.contains("notify") ||
          plain.actions.any(isSound)) {
        continue;
      }
      final sound = underride
          .where((r) =>
              r.ruleId == encryptedId &&
              r.enabled &&
              r.actions.contains("notify"))
          .firstOrNull
          ?.actions
          .where(isSound)
          .firstOrNull;
      if (sound == null) continue;
      underride[i] = matrix.PushRule(
        actions: [...plain.actions, sound],
        conditions: plain.conditions,
        default$: plain.default$,
        enabled: plain.enabled,
        pattern: plain.pattern,
        ruleId: plain.ruleId,
      );
      changed = true;
    }
    if (!changed) return null;
    return matrix.PushRuleSet(
      override: rules.override,
      content: rules.content,
      room: rules.room,
      sender: rules.sender,
      underride: underride,
    );
  }

  static bool _isThreadReplyRule(matrix.PushRule rule) =>
      rule.ruleId.startsWith(ThreadReplyRules.prefix) && !rule.default$;

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
  RoomPushRules(this.rules) : _loudness = _loudnessOf(rules);

  final matrix.PushRuleSet rules;

  final Map<int, matrix.PushruleEvaluator> _byMemberCount = {};

  /// Vommet issue 918: the rules that say how loud a loudness-neutral
  /// rule's notification is, null when [rules] have none.
  final RoomPushRules? _loudness;

  static RoomPushRules? _loudnessOf(matrix.PushRuleSet rules) {
    final set = MatrixPushRules.withoutLoudnessNeutralRules(rules);
    return set == null ? null : RoomPushRules._plain(set);
  }

  RoomPushRules._plain(this.rules) : _loudness = null;

  /// Vommet issue 918: the rules for a message in an encrypted room, null
  /// when they are the same ([MatrixPushRules.withEncryptedRowsSound]).
  late final RoomPushRules? _inEncryptedRoom = () {
    final set = MatrixPushRules.withEncryptedRowsSound(rules);
    return set == null ? null : RoomPushRules(set);
  }();

  /// What [rules] say to do for [event].
  matrix.EvaluatedPushRuleAction match(matrix.Event event) {
    final inEncryptedRoom = _inEncryptedRoom;
    if (inEncryptedRoom != null && event.room.encrypted) {
      return inEncryptedRoom.match(event);
    }

    final count = MatrixPushRules.joinedMemberCount(event.room);
    final evaluator = _byMemberCount[count] ??=
        matrix.PushruleEvaluator.fromRuleset(
            MatrixPushRules.forMemberCount(rules, count));
    final action = evaluator.match(event);

    // Vommet issue 918: a notification without a sound may come from a
    // loudness-neutral rule ("All Messages" set on the room, a thread
    // you're in); then the grid decides. Without those rules the same
    // event matches the same rule unless one of them had matched.
    final loudness = _loudness;
    if (loudness == null || !action.notify || action.sound != null) {
      return action;
    }
    final sound = loudness.match(event);
    if (!sound.notify || sound.sound == null) return action;
    // The SDK hands out the same action object for every match.
    return matrix.EvaluatedPushRuleAction()
      ..notify = true
      ..highlight = action.highlight
      ..sound = sound.sound;
  }
}
