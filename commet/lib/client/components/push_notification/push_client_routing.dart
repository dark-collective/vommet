import 'package:collection/collection.dart';
import 'package:commet/main.dart';

/// Vommet: which signed-in account a push is for.
///
/// Every account registers its pusher with `local_client_id` in the pusher
/// data. A Matrix push (what a UnifiedPush gateway forwards as is) carries
/// that data under `devices[].data`; Commet's own gateway used to flatten it
/// to the top level, which is the only place the app looked. With the
/// UnifiedPush gateway every push fell back to the rooms list cache, and a
/// push for a room missing from it was dropped: notifications from one
/// account only.
class PushClientRouting {
  /// The account id the push itself names, if any.
  static String? localClientId(Map<String, dynamic> message) {
    final direct = message["local_client_id"];
    if (direct is String) return direct;

    final devices = message["devices"];
    if (devices is List) {
      for (final device in devices) {
        if (device is! Map) continue;
        final data = device["data"];
        if (data is Map && data["local_client_id"] is String) {
          return data["local_client_id"] as String;
        }
      }
    }
    return null;
  }

  /// The account whose rooms (as last cached) include [roomId].
  static String? fromRoomsListCache(String? roomId) {
    if (roomId == null) return null;
    return preferences
        .getRoomsListCache()
        .entries
        .firstWhereOrNull((i) => i.value.contains(roomId))
        ?.key;
  }
}
