import 'dart:async';

import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/client/room.dart';
import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart' as matrix;

/// Vommet: messages deleted only for yourself ("Delete for me", like
/// Telegram's). Matrix can't delete a message for one person, so they're
/// hidden instead: the event ids live in the room's private account data,
/// so they stay hidden on your other Vommet devices. Other apps and the
/// other people in the room still see them.
class HiddenMessages {
  static const String type = "im.vommet.hidden_messages";

  /// Keeps the account data small; the oldest hides drop off first.
  static const int max = 1000;

  /// Bumps whenever a room's hidden messages change, here or on another
  /// device.
  static final ValueNotifier<int> changed = ValueNotifier(0);

  static final Map<matrix.Client, StreamSubscription> _watching = {};

  static matrix.Room? _matrixRoom(Room room) =>
      room is MatrixRoom ? room.matrixRoom : null;

  static bool supported(Room room) => _matrixRoom(room) != null;

  /// The room's hidden messages, oldest hide first.
  static List<String> of(Room room) {
    final mx = _matrixRoom(room);
    if (mx == null) return const [];
    _watch(mx.client);
    return parse(mx.roomAccountData[type]?.content);
  }

  static List<String> parse(Map<String, Object?>? content) {
    final hidden = content?["hidden"];
    if (hidden is! List) return const [];
    return hidden.whereType<String>().toSet().toList();
  }

  /// [current] plus [eventIds], newest last, at most [max].
  static List<String> added(List<String> current, Iterable<String> eventIds) {
    final adding = eventIds.toSet();
    final list = [...current.where((e) => !adding.contains(e)), ...adding];
    return list.length > max ? list.sublist(list.length - max) : list;
  }

  static bool isHidden(Room room, String eventId) => of(room).contains(eventId);

  static Future<void> hide(Room room, Iterable<String> eventIds) =>
      _set(room, added(of(room), eventIds));

  static Future<void> unhide(Room room, Iterable<String> eventIds) {
    final removing = eventIds.toSet();
    return _set(room, of(room).where((e) => !removing.contains(e)).toList());
  }

  static Future<void> _set(Room room, List<String> hidden) async {
    final mx = _matrixRoom(room);
    if (mx == null) return;
    final content = {"hidden": hidden};
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
