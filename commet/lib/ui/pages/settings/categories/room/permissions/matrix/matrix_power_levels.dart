// Vommet: pure helpers for the room/space Permissions page (power level
// lookups with the spec's defaults, privileged-user edits and the guards
// around them). Kept free of Flutter and the SDK Room so they can be
// unit tested.

/// Spec defaults for top-level `m.room.power_levels` keys that are absent.
const Map<String, int> _topLevelDefaults = {
  "invite": 0,
  "kick": 50,
  "ban": 50,
  "redact": 50,
  "events_default": 0,
  "state_default": 50,
  "users_default": 0,
};

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

/// The level a permission needs, following the spec's fallbacks when the key
/// is missing: `events.<type>` falls back to `state_default` for state events
/// and `events_default` for message events, `notifications.room` to 50, and
/// top-level keys to their spec defaults.
int resolvePermissionLevel(
  Map<String, Object?> content, {
  required String key,
  String? parent,
  bool isStateEvent = true,
}) {
  if (parent != null) {
    final map = content[parent];
    final value = map is Map ? _asInt(map[key]) : null;
    if (value != null) return value;
    if (parent == "notifications") return 50;
    return resolvePermissionLevel(content,
        key: isStateEvent ? "state_default" : "events_default");
  }

  return _asInt(content[key]) ?? _topLevelDefaults[key] ?? 50;
}

Object? _deepCopy(Object? value) {
  if (value is Map) {
    return <String, Object?>{
      for (final e in value.entries) e.key.toString(): _deepCopy(e.value)
    };
  }
  if (value is List) return value.map(_deepCopy).toList();
  return value;
}

/// A deep copy of power level content, so edits never touch the cached state.
Map<String, Object?> copyPowerLevels(Map<String, Object?> content) =>
    _deepCopy(content) as Map<String, Object?>;

/// Power level content with [userId] set to [level], or removed from `users`
/// (back to `users_default`) when [level] is null.
Map<String, Object?> powerLevelsWithUserLevel(
    Map<String, Object?> content, String userId, int? level) {
  final copy = copyPowerLevels(content);
  final users = copy["users"] is Map
      ? copy["users"] as Map<String, Object?>
      : <String, Object?>{};
  if (level == null) {
    users.remove(userId);
  } else {
    users[userId] = level;
  }
  copy["users"] = users;
  return copy;
}

/// Power level content with the given permissions applied. Keys are
/// `(parent, key)`; a null parent is a top-level key.
Map<String, Object?> powerLevelsWithPermissions(
    Map<String, Object?> content, Map<(String?, String), int> changes) {
  final copy = copyPowerLevels(content);
  for (final change in changes.entries) {
    final (parent, key) = change.key;
    if (parent == null) {
      copy[key] = change.value;
      continue;
    }
    final map = copy[parent] is Map
        ? copy[parent] as Map<String, Object?>
        : <String, Object?>{};
    map[key] = change.value;
    copy[parent] = map;
  }
  return copy;
}

class PowerLevelUser {
  const PowerLevelUser(this.userId, this.level, {this.isCreator = false});
  final String userId;
  final int level;

  /// Room version 12+ creators: unlimited power, not in `users`, can't be
  /// changed.
  final bool isCreator;
}

/// 2^53 - 1, what the SDK reports for room version 12+ creators.
const int creatorPowerLevel = 9007199254740991;

/// Users whose level differs from `users_default`, plus room version 12+
/// [creators], highest level first.
List<PowerLevelUser> privilegedUsers(Map<String, Object?> content,
    {Set<String> creators = const {}}) {
  final usersDefault = resolvePermissionLevel(content, key: "users_default");
  final result = <PowerLevelUser>[
    for (final c in creators)
      PowerLevelUser(c, creatorPowerLevel, isCreator: true)
  ];
  final users = content["users"];
  if (users is Map) {
    for (final e in users.entries) {
      final id = e.key.toString();
      final level = _asInt(e.value);
      if (level == null || level == usersDefault) continue;
      if (creators.contains(id)) continue;
      result.add(PowerLevelUser(id, level));
    }
  }
  result.sort((a, b) {
    final byLevel = b.level.compareTo(a.level);
    return byLevel != 0 ? byLevel : a.userId.compareTo(b.userId);
  });
  return result;
}

/// Whether someone at [ownLevel] may change a user's level: needs permission
/// to edit power levels, never for a creator, and (per the spec) only for
/// yourself or someone below your own level.
bool canChangeUserLevel({
  required bool canEditPowerLevels,
  required int ownLevel,
  required int targetLevel,
  required bool isSelf,
  bool isTargetCreator = false,
}) {
  if (!canEditPowerLevels || isTargetCreator) return false;
  return isSelf || targetLevel < ownLevel;
}

/// You can't raise anyone (yourself included) above your own level.
bool canAssignLevel({required int ownLevel, required int newLevel}) =>
    newLevel <= ownLevel;

/// Lowering your own level can't be undone by you, so it needs a confirm.
bool isSelfDemotion(
        {required bool isSelf,
        required int currentLevel,
        required int newLevel}) =>
    isSelf && newLevel < currentLevel;
