// Vommet issue 785: "Thread replies notify me: All threads / Only threads
// I'm in", for the account and per room, as server push rules so phone push
// follows it too.
//
// All the rules are user-defined UNDERRIDE rules whose ids start with
// [ThreadReplyRules.prefix]; other rules are never touched:
// - `<prefix>mute`: the account's "Only threads I'm in": a thread reply
//   doesn't notify. Underride, so mentions (override rules), keywords
//   (content rules) and a room's own level (room rules) still win, and the
//   main timeline and a thread's first message (not a thread reply) notify
//   as before.
// - `<prefix>mute.<room>` / `<prefix>all.<room>`: a room's own choice.
// - `<prefix>in.<root>`: a thread you're in (you replied or were mentioned
//   in it): its replies notify. Always above the mute rules, newest first;
//   the oldest are dropped past [ThreadReplyRules.maxThreads].
// Mute rules only match `m.room.message`: the homeserver can't read an
// encrypted reply's mentions, so encrypted replies are left to the device,
// which applies the same rules once it has decrypted them.

import 'package:matrix/matrix.dart' as matrix;

enum ThreadReplyNotify { all, mine }

typedef PutUnderrideRule = Future<void> Function(
    String ruleId, List<Object> actions, List<matrix.PushCondition> conditions,
    {String? before, String? after});

typedef DeleteUnderrideRule = Future<void> Function(String ruleId);

class ThreadReplyRules {
  static const String prefix = "im.vommet.thread_replies.";
  static const String globalMuteId = "${prefix}mute";
  static const int maxThreads = 200;

  /// Rule ids are path segments: no `/` or `\` (old event ids have `/`).
  static String _safe(String id) => id.replaceAll(RegExp(r"[/\\]"), "_");

  static String roomMuteId(String roomId) => "${prefix}mute.${_safe(roomId)}";
  static String roomAllId(String roomId) => "${prefix}all.${_safe(roomId)}";
  static String threadId(String rootId) => "${prefix}in.${_safe(rootId)}";

  static matrix.PushCondition _match(String key, String pattern) =>
      matrix.PushCondition(
          kind: matrix.PushRuleConditions.eventMatch.name,
          key: key,
          pattern: pattern);

  static matrix.PushCondition get _isThreadReply =>
      _match(r"content.m\.relates_to.rel_type", "m.thread");

  static matrix.PushCondition get _isMessage =>
      _match("type", "m.room.message");

  static matrix.PushCondition _inRoom(String roomId) =>
      _match("room_id", roomId);

  static List<matrix.PushRule> ours(matrix.PushRuleSet? rules) => [
        for (final r in rules?.underride ?? const <matrix.PushRule>[])
          if (r.ruleId.startsWith(prefix) && r.default$ != true) r,
      ];

  static bool _has(matrix.PushRuleSet? rules, String id) =>
      ours(rules).any((r) => r.ruleId == id);

  static bool _isMute(matrix.PushRule r) =>
      r.ruleId == globalMuteId || r.ruleId.startsWith("${prefix}mute.");

  static bool _isThread(matrix.PushRule r) =>
      r.ruleId.startsWith("${prefix}in.");

  /// The account's choice: "Only threads I'm in" while its mute rule exists.
  static ThreadReplyNotify accountChoice(matrix.PushRuleSet? rules) =>
      _has(rules, globalMuteId)
          ? ThreadReplyNotify.mine
          : ThreadReplyNotify.all;

  /// [roomId]'s own choice, null when it follows the account's.
  static ThreadReplyNotify? roomChoice(
      matrix.PushRuleSet? rules, String roomId) {
    if (_has(rules, roomMuteId(roomId))) return ThreadReplyNotify.mine;
    if (_has(rules, roomAllId(roomId))) return ThreadReplyNotify.all;
    return null;
  }

  static ThreadReplyNotify effective(
          matrix.PushRuleSet? rules, String roomId) =>
      roomChoice(rules, roomId) ?? accountChoice(rules);

  /// Whether a thread rule is kept for [rootId].
  static bool hasThread(matrix.PushRuleSet? rules, String rootId) =>
      _has(rules, threadId(rootId));

  /// Puts a mute rule below every rule of ours, so thread rules stay above.
  static Future<void> _putMute(matrix.PushRuleSet? rules, String id,
      List<matrix.PushCondition> conditions, PutUnderrideRule put,
      {Set<String> gone = const {}}) async {
    final list = [...ours(rules).where((r) => !gone.contains(r.ruleId))];
    await put(id, const [], conditions,
        after: list.isEmpty ? null : list.last.ruleId);
  }

  /// Puts a notifying rule above every rule of ours.
  static Future<void> _putAllow(matrix.PushRuleSet? rules, String id,
      List<matrix.PushCondition> conditions, PutUnderrideRule put,
      {Set<String> gone = const {}}) async {
    final list = [...ours(rules).where((r) => !gone.contains(r.ruleId))];
    await put(id, const ["notify"], conditions,
        before: list.isEmpty ? null : list.first.ruleId);
  }

  /// Sets the account's choice. Idempotent; "All threads" with no room left
  /// on "Only threads I'm in" removes the thread rules too.
  static Future<void> setAccountChoice(
      matrix.PushRuleSet? rules, ThreadReplyNotify choice,
      {required PutUnderrideRule put,
      required DeleteUnderrideRule delete}) async {
    final has = _has(rules, globalMuteId);
    if (choice == ThreadReplyNotify.mine && !has) {
      await _putMute(rules, globalMuteId, [_isMessage, _isThreadReply], put);
    } else if (choice == ThreadReplyNotify.all && has) {
      await delete(globalMuteId);
      await _dropUnusedThreads(rules, delete, accountMutes: false);
    }
  }

  /// Sets [roomId]'s own choice (null = follow the account's). Idempotent.
  static Future<void> setRoomChoice(
      matrix.PushRuleSet? rules, String roomId, ThreadReplyNotify? choice,
      {required PutUnderrideRule put,
      required DeleteUnderrideRule delete}) async {
    final muteId = roomMuteId(roomId), allId = roomAllId(roomId);
    final hasMute = _has(rules, muteId), hasAll = _has(rules, allId);
    final gone = <String>{};
    if (choice != ThreadReplyNotify.mine && hasMute) {
      await delete(muteId);
      gone.add(muteId);
    }
    if (choice != ThreadReplyNotify.all && hasAll) {
      await delete(allId);
      gone.add(allId);
    }
    if (choice == ThreadReplyNotify.mine && !hasMute) {
      await _putMute(
          rules, muteId, [_inRoom(roomId), _isMessage, _isThreadReply], put,
          gone: gone);
    } else if (choice == ThreadReplyNotify.all && !hasAll) {
      await _putAllow(rules, allId, [_inRoom(roomId), _isThreadReply], put,
          gone: gone);
    }
    if (hasMute && choice != ThreadReplyNotify.mine) {
      await _dropUnusedThreads(rules, delete,
          accountMutes: _has(rules, globalMuteId), skip: {muteId});
    }
  }

  /// Marks [rootId] in [roomId] as a thread you're in, when replies there
  /// would otherwise be muted. Returns whether a rule was added.
  static Future<bool> addThread(
      matrix.PushRuleSet? rules, String roomId, String rootId,
      {required PutUnderrideRule put,
      required DeleteUnderrideRule delete}) async {
    if (effective(rules, roomId) != ThreadReplyNotify.mine) return false;
    if (hasThread(rules, rootId)) return false;
    await _putAllow(
        rules,
        threadId(rootId),
        [
          _inRoom(roomId),
          _match(r"content.m\.relates_to.event_id", rootId),
        ],
        put);
    final threads = ours(rules).where(_isThread).toList();
    // The new rule is first; drop the oldest past the limit.
    for (final old in threads.skip(maxThreads - 1)) {
      await delete(old.ruleId);
    }
    return true;
  }

  /// Removes every thread rule once no mute rule is left.
  static Future<void> _dropUnusedThreads(
      matrix.PushRuleSet? rules, DeleteUnderrideRule delete,
      {required bool accountMutes, Set<String> skip = const {}}) async {
    if (accountMutes) return;
    final list = ours(rules);
    final mutesLeft = list.any((r) =>
        _isMute(r) && r.ruleId != globalMuteId && !skip.contains(r.ruleId));
    if (mutesLeft) return;
    for (final r in list.where(_isThread)) {
      await delete(r.ruleId);
    }
  }
}
