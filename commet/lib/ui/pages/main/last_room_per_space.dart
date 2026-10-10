/// Vommet: the room you were in when you left each space, so clicking the
/// space in the rail takes you back to it, as Discord does with servers.
/// Kept in memory only.
class LastRoomPerSpace {
  final Map<String, ({String roomId, bool textView})> _rooms = {};

  static String _key(String clientId, String spaceId) => "$clientId/$spaceId";

  /// Call when leaving a space. [roomId] is the open room, or null when the
  /// space's main page was showing (then the space reopens on its main
  /// page). A room outside the space (opened from a link without switching
  /// spaces) leaves the earlier entry alone.
  void leave(String clientId, String spaceId,
      {String? roomId, bool roomInSpace = false, bool textView = false}) {
    final key = _key(clientId, spaceId);
    if (roomId == null) {
      _rooms.remove(key);
    } else if (roomInSpace) {
      _rooms[key] = (roomId: roomId, textView: textView);
    }
  }

  ({String roomId, bool textView})? lookup(String clientId, String spaceId) =>
      _rooms[_key(clientId, spaceId)];
}
