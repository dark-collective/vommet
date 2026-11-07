import 'package:commet/client/space.dart';

/// Vommet (issue 307): the space to open with a room opened from a
/// notification or a link. Stays in [current] if the room is anywhere in it,
/// otherwise prefers a top-level space holding the room at any depth (its
/// room list shows subspaces as sections), and only then a subspace that
/// holds the room directly.
Space? spaceForRoom(Iterable<Space> spaces, String roomId, {Space? current}) {
  if (current != null && spaceContainsRoomDeep(current, roomId)) {
    return current;
  }

  for (var space in spaces) {
    if (space.isTopLevel && spaceContainsRoomDeep(space, roomId)) {
      return space;
    }
  }

  for (var space in spaces) {
    if (space.containsRoom(roomId)) return space;
  }

  return null;
}

/// Whether [roomId] is in [space] or any of its subspaces (loop-safe).
bool spaceContainsRoomDeep(Space space, String roomId) {
  final seen = <Space>{};
  final pending = <Space>[space];

  while (pending.isNotEmpty) {
    final next = pending.removeLast();
    if (!seen.add(next)) continue;
    if (next.containsRoom(roomId)) return true;
    pending.addAll(next.subspaces);
  }

  return false;
}
