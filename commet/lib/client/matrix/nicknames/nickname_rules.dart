/// Where your name in a room comes from (Vommet issue 69).
enum NicknameSource { room, space, global }

/// Your own nickname rules: one per space (applies to the space and every
/// room in it, subspaces included) and per-room overrides. Stored in account
/// data so they follow you across devices and can be re-applied after a join
/// or a global name change. The member events stay what others see.
class NicknameRules {
  static const accountDataType = "im.nether.vommet.nicknames";

  final Map<String, String> spaces;
  final Map<String, String> rooms;

  NicknameRules({Map<String, String>? spaces, Map<String, String>? rooms})
      : spaces = spaces ?? {},
        rooms = rooms ?? {};

  bool get isEmpty => spaces.isEmpty && rooms.isEmpty;

  static NicknameRules fromJson(Map<String, Object?>? json) {
    Map<String, String> read(Object? m) => {
          if (m is Map)
            for (final e in m.entries)
              if (e.key is String &&
                  e.value is String &&
                  (e.value as String).trim().isNotEmpty)
                e.key as String: (e.value as String).trim(),
        };
    return NicknameRules(
        spaces: read(json?["spaces"]), rooms: read(json?["rooms"]));
  }

  Map<String, Object?> toJson() => {"spaces": spaces, "rooms": rooms};

  /// The nickname for [roomId], and where it comes from. [parentSpaceIds]
  /// lists the spaces the room is in, nearest first (direct parents, then
  /// theirs). For a space itself, pass its own id first. Null name: use the
  /// global display name.
  (String?, NicknameSource, String?) resolve(
      String roomId, Iterable<String> parentSpaceIds) {
    final own = rooms[roomId];
    if (own != null) return (own, NicknameSource.room, roomId);

    for (final space in parentSpaceIds) {
      final name = spaces[space];
      if (name != null) return (name, NicknameSource.space, space);
    }

    return (null, NicknameSource.global, null);
  }

  /// Your new `m.room.member` content for showing [name] (null: no
  /// displayname) in place of [current], the server's copy. Null when
  /// nothing should be written: not joined, already showing [name], or (with
  /// [onlyIfShowing]) showing something other than that. Keeps the rest of
  /// the content (avatar etc.), minus a leftover leave/kick reason.
  static Map<String, Object?>? updatedMemberContent(
      Map<String, Object?> current, String? name,
      {String? onlyIfShowing}) {
    if (current["membership"] != "join") return null;
    if (onlyIfShowing != null && current["displayname"] != onlyIfShowing) {
      return null;
    }
    if (current["displayname"] == name) return null;

    final content = Map<String, Object?>.from(current)..remove("reason");
    if (name == null) {
      content.remove("displayname");
    } else {
      content["displayname"] = name;
    }
    return content;
  }
}
