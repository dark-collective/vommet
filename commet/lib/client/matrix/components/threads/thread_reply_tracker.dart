import 'package:commet/client/matrix/components/threads/thread_follows.dart';
import 'package:commet/client/matrix/components/threads/thread_read_scope.dart';
import 'package:commet/client/matrix/components/threads/thread_reply_rules.dart';
import 'package:commet/client/matrix/matrix_push_rules.dart';
import 'package:commet/debug/log.dart';
import 'package:matrix/matrix.dart' as matrix;

/// Vommet issues 785 and 1077: follows a thread for you when you reply in it
/// or someone mentions you in it (unless you unfollowed it; replying again
/// follows it again), and keeps a thread reply rule for each thread you
/// follow, so its replies notify in rooms where thread replies only notify
/// for threads you follow.
class ThreadReplyTracker {
  ThreadReplyTracker(this.client);

  final matrix.Client client;

  /// Roots whose rule was sent but isn't in the synced rules yet.
  final Set<String> _pending = {};

  /// Events that already followed their thread for you.
  final Set<String> _followedBy = {};

  /// Roots already looked up: whether you started or took part in them.
  final Map<String, bool> _rootIsMine = {};

  /// Older events (history loaded at sign-in) don't follow anything.
  static const Duration _freshFor = Duration(days: 1);

  static PutUnderrideRule putOn(matrix.Client client) =>
      (ruleId, actions, conditions, {before, after}) => client.setPushRule(
          matrix.PushRuleKind.underride, ruleId, actions,
          conditions: conditions, before: before, after: after);

  static DeleteUnderrideRule deleteOn(matrix.Client client) =>
      (ruleId) => client.deletePushRule(matrix.PushRuleKind.underride, ruleId);

  Future<void> onEvent(matrix.Event event) async {
    try {
      if (event.relationshipType != matrix.RelationshipTypes.thread) return;
      final rootId = event.relationshipEventId;
      if (rootId == null) return;
      final room = event.room;
      final own = event.senderId == client.userID;
      // The stored root still says you didn't take part (Vommet issue 1077).
      if (own) ThreadFollows.noteRepliedIn(room, rootId);
      final mentioned = !own && MatrixPushRules.match(event).highlight;
      final fresh = DateTime.now().difference(event.originServerTs) < _freshFor;
      var entry = ThreadFollows.entryOf(room, rootId);
      // A reply of yours after an unfollow, or a mention in a thread you
      // don't follow yet, follows it (which also adds its rule).
      if (fresh &&
          (own && entry?.follow == false ||
              mentioned &&
                  entry == null &&
                  !await _followedByDefault(event, rootId)) &&
          ThreadFollows.autoFollowApplies(entry,
              ownReply: own,
              eventTs: event.originServerTs.millisecondsSinceEpoch) &&
          _followedBy.add(event.eventId)) {
        await ThreadFollows.set(room, rootId, true, automatic: event.eventId);
        return;
      }
      final rules = client.globalPushRules;
      if (ThreadReplyRules.effective(rules, room.id) !=
          ThreadReplyNotify.mine) {
        return;
      }
      if (ThreadReplyRules.hasThread(rules, rootId)) {
        _pending.remove(rootId);
        return;
      }
      if (_pending.contains(rootId)) return;
      entry = ThreadFollows.entryOf(room, rootId);
      final followed = entry?.follow ??
          (own || mentioned || await _startedOrJoined(event, rootId));
      if (!followed) return;
      _pending.add(rootId);
      await ThreadReplyRules.addThread(rules, room.id, rootId,
          put: putOn(client), delete: deleteOn(client));
    } catch (e, s) {
      _pending.remove(event.relationshipEventId);
      Log.onError(e, s, content: "Couldn't keep a thread you follow");
    }
  }

  /// Whether a thread without an entry is followed anyway.
  Future<bool> _followedByDefault(matrix.Event event, String rootId) async =>
      ThreadReplyRules.hasThread(client.globalPushRules, rootId) ||
      await _startedOrJoined(event, rootId);

  Future<bool> _startedOrJoined(matrix.Event event, String rootId) async {
    final known = _rootIsMine[rootId];
    if (known != null) return known;
    if (_rootIsMine.length > 2000) _rootIsMine.clear();
    final root = await event.room.getEventById(rootId);
    return _rootIsMine[rootId] = root != null &&
        (root.senderId == client.userID ||
            ThreadReadScopes.startedOrParticipated(root));
  }
}
