import 'package:commet/client/matrix/components/threads/thread_reply_rules.dart';
import 'package:commet/client/matrix/matrix_push_rules.dart';
import 'package:commet/debug/log.dart';
import 'package:matrix/matrix.dart' as matrix;

/// Vommet issue 785: adds a thread to "Threads I'm in" (its replies notify
/// again) when you reply in it, someone mentions you in it, or someone
/// replies in a thread you started, in rooms where thread replies only
/// notify for threads you're in.
class ThreadReplyTracker {
  ThreadReplyTracker(this.client);

  final matrix.Client client;

  /// Roots whose rule was sent but isn't in the synced rules yet.
  final Set<String> _pending = {};

  /// Roots already looked up for their sender: whether it's you.
  final Map<String, bool> _rootIsMine = {};

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
      if (!await _imIn(event, rootId)) return;
      _pending.add(rootId);
      await ThreadReplyRules.addThread(rules, room.id, rootId,
          put: putOn(client), delete: deleteOn(client));
    } catch (e, s) {
      _pending.remove(event.relationshipEventId);
      Log.onError(e, s, content: "Couldn't add a thread you're in");
    }
  }

  Future<bool> _imIn(matrix.Event event, String rootId) async {
    final me = client.userID;
    if (event.senderId == me) return true;
    if (MatrixPushRules.match(event).highlight) return true;
    final known = _rootIsMine[rootId];
    if (known != null) return known;
    if (_rootIsMine.length > 2000) _rootIsMine.clear();
    final root = await event.room.getEventById(rootId);
    return _rootIsMine[rootId] = root != null && root.senderId == me;
  }
}
