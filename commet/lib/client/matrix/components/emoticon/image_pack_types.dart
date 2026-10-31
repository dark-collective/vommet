import 'package:matrix/matrix.dart' as matrix;

/// Vommet issue 731: image packs under the names the Matrix spec gave them
/// (v1.19, MSC2545) and the `im.ponies` names every client used before.
/// Vommet reads both and writes both, so packs keep working in clients that
/// only know one of them.
class ImagePackTypes {
  /// A pack in room state (one state event per pack, keyed by state key).
  static const roomPack = "m.room.image_pack";
  static const legacyRoomPack = "im.ponies.room_emotes";

  /// Both pack types, the spec's first (it is written first).
  static const roomPackTypes = [roomPack, legacyRoomPack];

  /// Account data listing the room packs turned on everywhere.
  static const enabledRooms = "m.image_pack.rooms";
  static const legacyEnabledRooms = "im.ponies.emote_rooms";

  static const enabledRoomsTypes = [enabledRooms, legacyEnabledRooms];

  /// MSC4389: an image's position in its pack.
  static const order = "order";
  static const unstableOrder = "fi.mau.msc4389.order";

  /// MSC4476: the room type of a room that only holds packs.
  static const packRoomType = "m.image_pack";
  static const unstablePackRoomType = "com.beeper.image_pack";

  static bool isPackRoomType(Object? type) =>
      type == packRoomType || type == unstablePackRoomType;

  static bool isRoomPackType(String type) =>
      type == roomPack || type == legacyRoomPack;

  /// The content to show for one pack (state key) that may exist under
  /// both types: the newer event wins (a delete is an empty content), the
  /// spec's type on a tie or when a time is unknown.
  static Map<String, dynamic> pick(
      {Map<String, dynamic>? stable,
      int? stableTs,
      Map<String, dynamic>? legacy,
      int? legacyTs}) {
    if (stable == null) return legacy ?? {};
    if (legacy == null) return stable;
    if (stableTs != null && legacyTs != null && legacyTs > stableTs) {
      return legacy;
    }
    return stable;
  }

  /// Every pack in [room]'s state, by state key, either type.
  static Map<String, Map<String, dynamic>> roomPacks(matrix.Room room) {
    final stable = room.states[roomPack] ?? const {};
    final legacy = room.states[legacyRoomPack] ?? const {};
    return {
      for (final key in {...stable.keys, ...legacy.keys})
        key: pick(
            stable: stable[key]?.content,
            stableTs: _ts(stable[key]),
            legacy: legacy[key]?.content,
            legacyTs: _ts(legacy[key])),
    };
  }

  static int? _ts(matrix.StrippedStateEvent? e) =>
      e is matrix.Event ? e.originServerTs.millisecondsSinceEpoch : null;

  /// The union of both enable lists: room id → pack state keys.
  static Map<String, Set<String>> mergeEnabledRooms(
      Map<String, dynamic>? stable, Map<String, dynamic>? legacy) {
    final result = <String, Set<String>>{};
    for (final content in [stable, legacy]) {
      final rooms = content?["rooms"];
      if (rooms is! Map) continue;
      for (final entry in rooms.entries) {
        final packs = entry.value;
        if (entry.key is! String || packs is! Map) continue;
        result
            .putIfAbsent(entry.key as String, () => {})
            .addAll(packs.keys.whereType<String>());
      }
    }
    return result;
  }

  /// The enable list as account-data content.
  static Map<String, dynamic> enabledRoomsContent(
          Map<String, Set<String>> rooms) =>
      {
        "rooms": {
          for (final entry in rooms.entries)
            if (entry.value.isNotEmpty)
              entry.key: {for (final key in entry.value) key: {}},
        }
      };

  /// A copy of a pack's [content] with every image numbered 0, 1, 2…
  /// (MSC4389, under both names): servers don't keep JSON key order, so
  /// without numbers the order a pack was saved in can be lost. Numbered
  /// images keep their order; images without a number (just added, or
  /// added by another client) go after them, in map order.
  static Map<String, dynamic> withOrder(Map<String, dynamic> content) {
    final images = content["images"];
    if (images is! Map || images.isEmpty) return content;
    final entries = images.entries
        .where((e) => e.key is String)
        .map((e) => MapEntry(e.key as String, e.value));
    final numbered = sortedImages(
        {for (final e in entries.where(_hasOrder)) e.key: e.value});
    final rest = entries.where((e) => !_hasOrder(e));
    var i = 0;
    return {
      ...content,
      "images": {
        for (final entry in [...numbered, ...rest])
          entry.key: entry.value is Map
              ? {
                  ...(entry.value as Map),
                  order: i,
                  unstableOrder: i++,
                }
              : entry.value,
      },
    };
  }

  static bool _hasOrder(MapEntry<String, dynamic> e) =>
      _orderOf(e.value) != null;

  static int? _orderOf(Object? value) {
    if (value is! Map) return null;
    final o = value[order] ?? value[unstableOrder];
    return o is int ? o : null;
  }

  /// [images] sorted by their MSC4389 number (missing counts as 0, as the
  /// MSC says; ties keep their saved order).
  static List<MapEntry<String, T>> sortedImages<T>(Map<String, T> images) {
    final entries = images.entries.toList();
    final positions = {
      for (var i = 0; i < entries.length; i++) entries[i].key: i
    };
    entries.sort((a, b) {
      final byOrder =
          (_orderOf(a.value) ?? 0).compareTo(_orderOf(b.value) ?? 0);
      return byOrder != 0
          ? byOrder
          : positions[a.key]!.compareTo(positions[b.key]!);
    });
    return entries;
  }

  /// MSC4476 asks for pack rooms with messages off. Only admins change the
  /// room; members at the editor level (50) edit packs and nothing else, so
  /// they can't wipe a pack by redacting it either.
  static Map<String, dynamic> packRoomPowerLevels(String markerType) => {
        "events_default": 100,
        "redact": 100,
        "events": {
          roomPack: 50,
          legacyRoomPack: 50,
          markerType: 100,
          "m.room.name": 50,
          "m.room.avatar": 50,
          "m.room.topic": 50,
          "m.room.canonical_alias": 100,
          "m.room.power_levels": 100,
          "m.room.join_rules": 100,
          "m.room.history_visibility": 100,
          "m.room.encryption": 100,
          "m.room.tombstone": 100,
          "m.room.server_acl": 100,
          "m.space.child": 100,
          "m.space.parent": 100,
        },
      };
}
