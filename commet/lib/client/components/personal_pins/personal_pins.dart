import 'dart:async';

import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/client/room.dart';
import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart' as matrix;

/// Vommet: messages pinned only for yourself ("Pin for me", like Telegram's).
/// They live in the room's private account data, so they follow you to your
/// other devices and nobody else in the room sees them. Other apps don't
/// show them.
class PersonalPins {
  static const String type = "im.vommet.personal_pins";

  /// Bumps whenever a room's personal pins change, here or on another device.
  static final ValueNotifier<int> changed = ValueNotifier(0);

  static final Map<matrix.Client, StreamSubscription> _watching = {};

  static matrix.Room? _matrixRoom(Room room) =>
      room is MatrixRoom ? room.matrixRoom : null;

  static bool supported(Room room) => _matrixRoom(room) != null;

  /// The room's personal pins, oldest first.
  static List<String> of(Room room) {
    final mx = _matrixRoom(room);
    if (mx == null) return const [];
    _watch(mx.client);
    return parse(mx.roomAccountData[type]?.content);
  }

  static List<String> parse(Map<String, Object?>? content) {
    final pinned = content?["pinned"];
    if (pinned is! List) return const [];
    return pinned.whereType<String>().toSet().toList();
  }

  static bool isPinned(Room room, String eventId) => of(room).contains(eventId);

  static Future<void> pin(Room room, String eventId) =>
      _set(room, [...of(room).where((e) => e != eventId), eventId]);

  static Future<void> unpin(Room room, String eventId) =>
      _set(room, of(room).where((e) => e != eventId).toList());

  static Future<void> _set(Room room, List<String> pinned) async {
    final mx = _matrixRoom(room);
    if (mx == null) return;
    final content = {"pinned": pinned};
    await mx.client
        .setAccountDataPerRoom(mx.client.userID!, mx.id, type, content);
    // Show it now rather than when the sync echoes it back.
    mx.roomAccountData[type] = matrix.BasicEvent(type: type, content: content);
    changed.value++;
  }

  static void _watch(matrix.Client client) {
    if (_watching.containsKey(client)) return;
    _watching[client] = client.onSync.stream.listen((sync) {
      final rooms = sync.rooms?.join?.values ?? const [];
      if (rooms.any((r) => r.accountData?.any((e) => e.type == type) == true)) {
        changed.value++;
      }
    });
  }
}
