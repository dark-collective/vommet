import 'package:commet/client/matrix/matrix_push_rules.dart';
import 'package:matrix/matrix.dart' as matrix;

/// What the account's push rules say about an event.
class PushVerdict {
  const PushVerdict({
    required this.notify,
    required this.sound,
    required this.highlight,
  });

  final bool notify;
  final bool sound;
  final bool highlight;

  /// The actions of a rule, as the SDK's evaluator reads them.
  factory PushVerdict.fromActions(List<Object?> actions) {
    var notify = false;
    var sound = false;
    var highlight = false;
    for (final action in actions) {
      if (action == "notify") {
        notify = true;
      } else if (action == "dont_notify") {
        notify = false;
      } else if (action is Map) {
        if (action["set_tweak"] == "highlight") {
          final value = action["value"];
          highlight = value is bool ? value : true;
        } else if (action["set_tweak"] == "sound") {
          sound = true;
        }
      }
    }
    return PushVerdict(notify: notify, sound: sound, highlight: highlight);
  }

  @override
  String toString() =>
      "PushVerdict(notify: $notify, sound: $sound, highlight: $highlight)";
}

/// What the evaluator knows about the room. A null field is unknown: a rule
/// that needs it makes the verdict undetermined.
class PushRoomFacts {
  const PushRoomFacts({
    required this.roomId,
    required this.ownUserId,
    this.joinedMemberCount,
    this.ownDisplayName,
    this.senderPowerLevel,
    this.notificationPowerLevels,
    this.encryptedRoom = false,
  });

  final String roomId;
  final String ownUserId;
  final int? joinedMemberCount;
  final String? ownDisplayName;
  final int? senderPowerLevel;

  /// The power levels' `notifications` (e.g. "room" -> 50); a missing key
  /// means 50, as in the spec.
  final Map<String, int>? notificationPowerLevels;

  /// Vommet issue 918: the room is encrypted (its messages are checked
  /// decrypted, see [MatrixPushRules.withEncryptedRowsSound]).
  final bool encryptedRoom;
}

/// Thrown when an input a rule needs is missing or can't be read.
class _Undetermined implements Exception {
  const _Undetermined(this.reason);

  final String reason;

  @override
  String toString() => reason;
}

/// A condition kind this check doesn't know (e.g. Tuwunel's
/// `im.nheko.msc3664.related_event_match`).
class _UnknownKind extends _Undetermined {
  const _UnknownKind(super.reason);
}

/// Vommet issue 719 follow-up: the account's push rules checked on the
/// device without a client, for the background service (pushes in the
/// `event_id_only` format carry no tweaks). Mirrors the SDK's
/// `PushruleEvaluator` (flattening, globs, escaping), but answers null
/// instead of guessing whenever an input that could decide the outcome is
/// missing or unknown, so the caller falls back to playing a sound.
class PushRuleCheck {
  /// Why the last [evaluate] answered null, for the log.
  static String? lastReason;

  /// The verdict of [rules] for [eventJson] (the whole event, see
  /// [ruleInput]), or null when it can't be fully determined.
  static PushVerdict? evaluate(matrix.PushRuleSet rules,
      Map<String, Object?> eventJson, PushRoomFacts facts) {
    lastReason = null;
    try {
      if (eventJson["type"] == matrix.EventTypes.Encrypted) {
        throw const _Undetermined("event still encrypted");
      }
      if (facts.encryptedRoom) {
        rules = MatrixPushRules.withEncryptedRowsSound(rules) ?? rules;
      }
      final verdict = _evaluate(rules, eventJson, facts);
      if (!verdict.notify || verdict.sound) return verdict;

      // Vommet issue 918: "All Messages" set on the room and "Threads I'm
      // in" say nothing about the sound (see
      // MatrixPushRules.isLoudnessNeutral): the account's grid decides, as
      // in the app. Without those rules the same event matches the same
      // rule unless one of them had matched.
      final grid = MatrixPushRules.withoutLoudnessNeutralRules(rules);
      if (grid == null) return verdict;
      final loudness = _evaluate(grid, eventJson, facts);
      if (!loudness.notify || !loudness.sound) return verdict;
      return PushVerdict(
          notify: true, sound: true, highlight: verdict.highlight);
    } on _Undetermined catch (e) {
      lastReason = e.reason;
      return null;
    } catch (e) {
      lastReason = "error: ${e.runtimeType}";
      return null;
    }
  }

  static PushVerdict _evaluate(matrix.PushRuleSet rules,
      Map<String, Object?> eventJson, PushRoomFacts facts,
      [Set<matrix.PushRule> skip = const {}]) {
    final content = eventJson["content"];
    if (content is Map<String, Object?> &&
        MatrixPushRules.hasMentions(content)) {
      rules = MatrixPushRules.withoutLegacyMentionRules(rules);
    }

    final flat = flatten(eventJson);
    flat["room_id"] = facts.roomId;
    final sender = eventJson["sender"];

    // Vommet issue 1047: a rule with an unknown condition kind is decided
    // both ways. Notify and sound if either way does (never silent by
    // mistake); highlight only as if the rule didn't match (no made-up
    // highlights).
    PushVerdict both(matrix.PushRule rule) {
      final skipped = _evaluate(rules, eventJson, facts, {...skip, rule});
      final matched = PushVerdict.fromActions(rule.actions);
      return PushVerdict(
          notify: matched.notify || skipped.notify,
          sound: matched.sound || skipped.sound,
          highlight: skipped.highlight);
    }

    for (final rule in rules.override ?? const <matrix.PushRule>[]) {
      if (skip.contains(rule)) continue;
      try {
        if (_matches(rule, rule.conditions, flat, facts)) {
          return PushVerdict.fromActions(rule.actions);
        }
      } on _UnknownKind {
        return both(rule);
      }
    }

    for (final rule in rules.content ?? const <matrix.PushRule>[]) {
      if (!rule.enabled) continue;
      final pattern = rule.pattern;
      if (pattern == null) {
        throw _Undetermined("content rule without pattern");
      }
      final condition = matrix.PushCondition(
          kind: "event_match", key: "content.body", pattern: pattern);
      if (_matches(rule, [condition], flat, facts)) {
        return PushVerdict.fromActions(rule.actions);
      }
    }

    for (final rule in rules.room ?? const <matrix.PushRule>[]) {
      if (rule.enabled && rule.ruleId == facts.roomId) {
        return PushVerdict.fromActions(rule.actions);
      }
    }

    for (final rule in rules.sender ?? const <matrix.PushRule>[]) {
      if (rule.enabled && rule.ruleId == sender) {
        return PushVerdict.fromActions(rule.actions);
      }
    }

    for (final rule in rules.underride ?? const <matrix.PushRule>[]) {
      if (skip.contains(rule)) continue;
      try {
        if (_matches(rule, rule.conditions, flat, facts)) {
          return PushVerdict.fromActions(rule.actions);
        }
      } on _UnknownKind {
        return both(rule);
      }
    }

    return const PushVerdict(notify: false, sound: false, highlight: false);
  }

  /// Whether an enabled [rule] matches. Throws [_Undetermined] when no
  /// condition fails but one can't be decided.
  static bool _matches(
      matrix.PushRule rule,
      List<matrix.PushCondition>? conditions,
      Map<String, Object?> flat,
      PushRoomFacts facts) {
    if (!rule.enabled) return false;
    _Undetermined? unknown;
    _UnknownKind? unknownKind;
    for (final condition in conditions ?? const <matrix.PushCondition>[]) {
      bool holds;
      try {
        holds = _condition(condition, flat, facts);
      } on _Undetermined catch (e) {
        // Server default rule ids only: a user's own rule may be named
        // after a room or a person.
        final id = rule.ruleId.startsWith(".") ? rule.ruleId : "own rule";
        if (e is _UnknownKind) {
          unknownKind ??= _UnknownKind("$id: ${e.reason}");
        } else {
          unknown ??= _Undetermined("$id: ${e.reason}");
        }
        continue;
      }
      if (!holds) return false;
    }
    // Missing facts outrank an unknown kind: then nothing is decided.
    if (unknown != null) throw unknown;
    if (unknownKind != null) throw unknownKind;
    return true;
  }

  static bool _condition(matrix.PushCondition condition,
      Map<String, Object?> flat, PushRoomFacts facts) {
    switch (condition.kind) {
      case "event_match":
        final key = condition.key;
        final pattern = condition.pattern;
        if (key == null || pattern == null) {
          throw const _Undetermined("event_match without key or pattern");
        }
        final field = _unescapeKey(key);
        final value = flat[field];
        if (value is! String) return false;
        return globToRegExp(pattern, wordBoundary: field == "content.body")
            .hasMatch(value);
      case "event_property_is":
      case "event_property_contains":
        final key = condition.key;
        final expected = condition.value;
        if (key == null ||
            !(expected == null ||
                expected is String ||
                expected is int ||
                expected is bool)) {
          throw _Undetermined("${condition.kind} unreadable");
        }
        final field = _unescapeKey(key);
        if (condition.kind == "event_property_is") {
          return flat.containsKey(field) && flat[field] == expected;
        }
        final value = flat[field];
        return value is Iterable && value.contains(expected);
      case "room_member_count":
        final count = facts.joinedMemberCount;
        if (count == null) {
          throw const _Undetermined("member count unknown");
        }
        final holds = MatrixPushRules.memberCountMatches(condition.is$, count);
        if (holds == null) {
          throw const _Undetermined("room_member_count unreadable");
        }
        return holds;
      case "contains_display_name":
        final body = flat["content.body"];
        if (body is! String) return false;
        final name = facts.ownDisplayName;
        if (name == null) {
          throw const _Undetermined("own display name unknown");
        }
        if (name.isEmpty) return false;
        return RegExp("(^|\\W)${RegExp.escape(name)}(\$|\\W)",
                caseSensitive: false)
            .hasMatch(body);
      case "sender_notification_permission":
        final key = condition.key;
        if (key == null) {
          throw const _Undetermined("sender_notification_permission key");
        }
        final levels = facts.notificationPowerLevels;
        final senderLevel = facts.senderPowerLevel;
        if (levels == null || senderLevel == null) {
          throw const _Undetermined("power levels unknown");
        }
        return senderLevel >= (levels[key] ?? 50);
      case "im.nheko.msc3664.related_event_match":
        // Tuwunel's default reply rule. The related event isn't at hand,
        // but an event with no relation can't match it.
        if (!flat.keys.any((k) => k.startsWith("content.m.relates_to."))) {
          return false;
        }
        throw _UnknownKind("related event unknown (${condition.kind})");
      default:
        throw _UnknownKind("unknown condition kind ${condition.kind}");
    }
  }

  /// `\.` in a condition key is a dot in a property name.
  static String _unescapeKey(String key) => key.replaceAll(r"\.", ".");

  /// A push rule glob (`*`, `?`) as the SDK matches it: the whole value,
  /// or for `content.body` a run of words in it, ignoring case.
  static RegExp globToRegExp(String glob, {required bool wordBoundary}) {
    final pattern =
        RegExp.escape(glob).replaceAll("\\*", ".*").replaceAll("\\?", ".");
    return wordBoundary
        ? RegExp("(^|\\W)$pattern(\$|\\W)", caseSensitive: false)
        : RegExp("^$pattern\$", caseSensitive: false);
  }

  /// Vommet issue 978: the whole (decrypted) event, as the SDK's evaluator
  /// reads it, so a rule on `state_key`, `unsigned` or any other key decides
  /// the same way as with the app open. `room_id` is set to [roomId].
  static Map<String, Object?> ruleInput(
          Map<String, Object?> eventJson, String roomId) =>
      {...eventJson, "room_id": roomId};

  /// [json] with nested objects as dotted keys, as the SDK flattens events.
  static Map<String, Object?> flatten(Map<String, Object?> json,
      [String prefix = "", Map<String, Object?>? into]) {
    final flat = into ?? <String, Object?>{};
    for (final entry in json.entries) {
      final key = prefix.isEmpty ? entry.key : "$prefix.${entry.key}";
      final value = entry.value;
      if (value is Map) {
        flatten(Map<String, Object?>.from(value), key, flat);
      } else {
        flat[key] = value;
      }
    }
    return flat;
  }
}
