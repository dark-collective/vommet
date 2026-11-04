import 'package:matrix/matrix.dart' as matrix;

/// Vommet: the relation the SDK gives a file sent in a thread (see
/// `matrix.Room.sendEvent`), so its upload placeholder is already a thread
/// reply (Vommet issue 301).
Map<String, dynamic> threadFileRelation(
    String threadRootEventId, String? threadLastEventId) {
  return {
    "event_id": threadRootEventId,
    "rel_type": matrix.RelationshipTypes.thread,
    "is_falling_back": true,
    if (threadLastEventId != null)
      "m.in_reply_to": {"event_id": threadLastEventId},
  };
}
