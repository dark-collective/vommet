import 'dart:collection';
import 'dart:convert';

/// Vommet: the room you were in when you left each space, so clicking the
/// space in the rail takes you back to it, as Discord does with servers.
/// With [saved]/[onChanged], also kept on this device across restarts.
class LastRoomPerSpace {
  /// [saved] is what [onChanged] last wrote (JSON); anything unreadable
  /// starts empty.
  LastRoomPerSpace({String? saved, this.onChanged}) {
    if (saved == null || saved.isEmpty) return;
    try {
      final json = jsonDecode(saved) as Map<String, dynamic>;
      for (final entry in json.entries) {
        final value = entry.value as Map<String, dynamic>;
        _rooms[entry.key] =
            (roomId: value["r"] as String, textView: value["t"] == true);
      }
    } catch (_) {
      _rooms.clear();
    }
  }

  /// Called with the new JSON whenever an entry changes.
  final void Function(String json)? onChanged;

  /// Oldest entries are dropped past this, so the saved map stays small.
  static const maxEntries = 200;

  // Insertion-ordered: the most recently left space is last.
  final LinkedHashMap<String, ({String roomId, bool textView})> _rooms =
      LinkedHashMap();

  static String _key(String clientId, String spaceId) => "$clientId/$spaceId";

  /// Call when leaving a space. [roomId] is the open room, or null when the
  /// space's main page was showing (then the space reopens on its main
  /// page). A room outside the space (opened from a link without switching
  /// spaces) leaves the earlier entry alone.
  void leave(String clientId, String spaceId,
      {String? roomId, bool roomInSpace = false, bool textView = false}) {
    final key = _key(clientId, spaceId);
    if (roomId == null) {
      if (_rooms.remove(key) != null) _save();
    } else if (roomInSpace) {
      _rooms.remove(key);
      _rooms[key] = (roomId: roomId, textView: textView);
      while (_rooms.length > maxEntries) {
        _rooms.remove(_rooms.keys.first);
      }
      _save();
    }
  }

  ({String roomId, bool textView})? lookup(String clientId, String spaceId) =>
      _rooms[_key(clientId, spaceId)];

  void _save() {
    final save = onChanged;
    if (save == null) return;
    save(jsonEncode({
      for (final e in _rooms.entries)
        e.key: {"r": e.value.roomId, if (e.value.textView) "t": true},
    }));
  }
}
