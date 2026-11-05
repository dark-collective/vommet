import 'dart:async';
import 'package:commet/client/client.dart';

/// A canceled scheduled message waiting for its exact room's composer.
/// This is an in-memory edit handoff, never a scheduling or sending queue.
class ScheduledEditHandoff {
  static final Expando<Map<String, String>> _pending = Expando();
  static final StreamController<Client> _changed = StreamController.broadcast();
  static Stream<Client> get changed => _changed.stream;

  static bool contains(Room room) =>
      _pending[room.client]?.containsKey(room.identifier) == true;

  static void put(Room room, String text) {
    (_pending[room.client] ??= {})[room.identifier] = text;
    _changed.add(room.client);
  }

  static String? take(Room room) =>
      _pending[room.client]?.remove(room.identifier);

  static void forget(Client client) {
    _pending[client] = null;
  }
}
