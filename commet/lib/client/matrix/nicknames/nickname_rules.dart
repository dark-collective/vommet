/// Where your name in a room comes from (Vommet issue 69).
enum NicknameSource { room, space, global }

/// Your own nickname rules: one per space (applies to the space and every
/// room in it, subspaces included) and per-room overrides. Stored in account
/// data so they follow you across devices and can be re-applied after a join
/// or a global name change. The member events stay what others see.
///
/// The same shape holds your per-place pictures (values are mxc URIs), under
/// [avatarAccountDataType]: a separate account data type, so a build that
/// only knows names can't drop the pictures when it saves a name.
class NicknameRules {
  static const accountDataType = "im.nether.vommet.nicknames";
  static const avatarAccountDataType = "im.nether.vommet.place_avatars";

  final Map<String, String> spaces;
  final Map<String, String> rooms;

  /// Keys a newer build added; written back untouched.
  final Map<String, Object?> _other;

  NicknameRules(
      {Map<String, String>? spaces,
      Map<String, String>? rooms,
      Map<String, Object?>? other})
      : spaces = spaces ?? {},
        rooms = rooms ?? {},
        _other = other ?? {};

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
        spaces: read(json?["spaces"]),
        rooms: read(json?["rooms"]),
        other: {
          for (final e in json?.entries ?? <MapEntry<String, Object?>>[])
            if (e.key != "spaces" && e.key != "rooms") e.key: e.value,
        });
  }

  Map<String, Object?> toJson() =>
      {..._other, "spaces": spaces, "rooms": rooms};

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
  ///
  /// With [setAvatar], the picture becomes [avatar] (null: none) too, in the
  /// same write; without it the picture stays. With [setName] false only the
  /// picture is changed ([name] and [onlyIfShowing] are ignored).
  static Map<String, Object?>? updatedMemberContent(
      Map<String, Object?> current, String? name,
      {String? onlyIfShowing,
      bool setName = true,
      bool setAvatar = false,
      String? avatar}) {
    if (current["membership"] != "join") return null;
    if (setName &&
        onlyIfShowing != null &&
        current["displayname"] != onlyIfShowing) {
      return null;
    }
    final nameChanges = setName && current["displayname"] != name;
    final avatarChanges = setAvatar && current["avatar_url"] != avatar;
    if (!nameChanges && !avatarChanges) return null;

    final content = Map<String, Object?>.from(current)..remove("reason");
    if (nameChanges) {
      if (name == null) {
        content.remove("displayname");
      } else {
        content["displayname"] = name;
      }
    }
    if (avatarChanges) {
      if (avatar == null) {
        content.remove("avatar_url");
      } else {
        content["avatar_url"] = avatar;
      }
    }
    return content;
  }
}
