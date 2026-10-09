import 'package:commet/client/client.dart';
import 'package:commet/client/components/room_component.dart';

/// Rooms whose stored history can be thrown away and loaded again from the
/// server ("Reload history" in the room menu), for when it has a gap.
abstract class HistoryReloadComponent<R extends Client, T extends Room>
    implements RoomComponent<R, T> {
  /// Forgets the room's stored timeline and loads it again from the server.
  Future<void> reloadHistory();

  /// True while a reload is running.
  bool get isReloading;
}
