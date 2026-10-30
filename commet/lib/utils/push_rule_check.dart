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
  });

  final String roomId;
  final String ownUserId;
  final int? joinedMemberCount;
  final String? ownDisplayName;
  final int? senderPowerLevel;

  /// The power levels' `notifications` (e.g. "room" -> 50); a missing key
  /// means 50, as in the spec.
  final Map<String, int>? notificationPowerLevels;
}

/// Thrown when an input a rule needs is missing or can't be read.
class _Undetermined implements Exception {
  const _Undetermined(this.reason);

  final String reason;

  @override
  String toString() => reason;
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

  /// The verdict of [rules] for [eventJson] (type, content, sender), or
  /// null when it can't be fully determined.
  static PushVerdict? evaluate(matrix.PushRuleSet rules,
      Map<String, Object?> eventJson, PushRoomFacts facts) {
    lastReason = null;
    try {
      if (eventJson["type"] == matrix.EventTypes.Encrypted) {
        throw const _Undetermined("event still encrypted");
      }
      return _evaluate(rules, eventJson, facts);
    } on _Undetermined catch (e) {
      lastReason = e.reason;
      return null;
    } catch (e) {
      lastReason = "error: ${e.runtimeType}";
      return null;
    }
  }

  static PushVerdict _evaluate(matrix.PushRuleSet rules,
      Map<String, Object?> eventJson, PushRoomFacts facts) {
    final content = eventJson["content"];
    if (content is Map<String, Object?> &&
        MatrixPushRules.hasMentions(content)) {
      rules = MatrixPushRules.withoutLegacyMentionRules(rules);
    }

    final flat = flatten(eventJson);
    flat["room_id"] = facts.roomId;
    final sender = eventJson["sender"];

    for (final rule in rules.override ?? const <matrix.PushRule>[]) {
      if (_matches(rule, rule.conditions, flat, facts)) {
        return PushVerdict.fromActions(rule.actions);
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
      if (_matches(rule, rule.conditions, flat, facts)) {
        return PushVerdict.fromActions(rule.actions);
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
    for (final condition in conditions ?? const <matrix.PushCondition>[]) {
      bool holds;
      try {
        holds = _condition(condition, flat, facts);
      } on _Undetermined catch (e) {
        unknown ??= _Undetermined("${rule.ruleId}: ${e.reason}");
        continue;
      }
      if (!holds) return false;
    }
    if (unknown != null) throw unknown;
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
      default:
        throw _Undetermined("unknown condition kind ${condition.kind}");
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
