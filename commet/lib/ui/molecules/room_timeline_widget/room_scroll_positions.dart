import 'dart:ui';

/// Vommet issue 634: where a room's timeline was scrolled to when it was
/// left, so coming back opens it there instead of at the newest messages.
/// Kept in memory only, for as long as the app runs.
class RoomScrollPosition {
  const RoomScrollPosition(this.eventId, this.gapToBottom);

  /// The lowest event that was on screen.
  final String eventId;

  /// Distance from the bottom of the view up to that event's bottom edge;
  /// negative when the event reached past the bottom of the view.
  final double gapToBottom;
}

class RoomScrollPositions {
  static final Map<String, RoomScrollPosition> _positions = {};

  static String key(String clientId, String roomId) => "$clientId|$roomId";

  static RoomScrollPosition? get(String key) => _positions[key];

  static void save(String key, RoomScrollPosition position) =>
      _positions[key] = position;

  static void forget(String key) => _positions.remove(key);

  static void clear() => _positions.clear();

  /// Picks the lowest event visible in [viewport] from the laid-out
  /// [entries] (event id and on-screen bounds), or null when none shows.
  static RoomScrollPosition? anchorFor(
      Rect viewport, Iterable<(String, Rect)> entries) {
    RoomScrollPosition? best;
    for (final (eventId, bounds) in entries) {
      if (bounds.height <= 0) continue;
      if (bounds.bottom <= viewport.top || bounds.top >= viewport.bottom) {
        continue;
      }
      final gap = viewport.bottom - bounds.bottom;
      if (best == null || gap < best.gapToBottom) {
        best = RoomScrollPosition(eventId, gap);
      }
    }
    return best;
  }
}
