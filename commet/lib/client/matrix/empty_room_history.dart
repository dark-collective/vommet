import 'package:matrix/matrix.dart' as matrix;
import 'package:matrix/msc_extensions/msc_4186_sliding_sync/msc_4186_sliding_sync.dart'
    show SyncGap;

/// Vommet issue 945: a joined room can have no stored events and no token to
/// page back from. Sliding sync sends the rooms in the room list with a few
/// events at most and not always a `prev_batch`; a room sent without either,
/// with no new messages since, is stored like that. The
/// SDK still says history can be loaded (an empty timeline always can), but
/// with nothing stored and no token each request does nothing, so the room
/// stayed empty and "Load older messages" did nothing either.
///
/// Such a timeline pages back from the room's newest event instead, once
/// ([SyncGap.prevBatch], as for the gaps sliding sync leaves). If that finds
/// nothing either, the room has no history to load.
class EmptyRoomHistory {
  bool _pagedFromNewest = false;

  static bool _nothingToPageFrom(matrix.Timeline timeline) {
    final room = timeline.room;
    return timeline.events.isEmpty &&
        !timeline.isFragmentedTimeline &&
        room.membership == matrix.Membership.join &&
        room.prev_batch == null;
  }

  /// Call before each [matrix.Timeline.requestHistory].
  void beforeRequest(matrix.Timeline timeline) {
    if (_pagedFromNewest || !_nothingToPageFrom(timeline)) return;
    _pagedFromNewest = true;
    timeline.room.prev_batch = SyncGap.prevBatch;
  }

  /// [matrix.Timeline.canRequestHistory], except for an empty timeline that
  /// has paged back from the newest event and found nothing.
  bool canRequest(matrix.Timeline timeline) =>
      timeline.canRequestHistory &&
      !(_pagedFromNewest && _nothingToPageFrom(timeline));
}
