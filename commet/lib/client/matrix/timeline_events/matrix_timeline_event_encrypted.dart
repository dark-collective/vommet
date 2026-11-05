import 'package:commet/client/client.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/client/timeline_events/timeline_event_encrypted.dart';
import 'package:matrix/matrix.dart' as matrix;

class MatrixTimelineEventEncrypted extends MatrixTimelineEvent
    implements TimelineEventEncrypted {
  MatrixTimelineEventEncrypted(super.event, {required super.client});

  @override
  Future<TimelineEvent<Client>?> attemptDecrypt(Room room) async {
    if (room is! MatrixRoom) {
      return null;
    }

    var encryption = event.room.client.encryption;
    if (encryption == null) {
      return null;
    }

    try {
      // Loads the key from the online key backup if there is one, otherwise
      // asks our other devices. Throws when the key can't be requested.
      await event.requestKey();
    } catch (_) {}

    // Decrypt this event rather than fetching it again: room.getEvent returns
    // the stored copy, still encrypted, when the event is in the database.
    var decrypted = await encryption.decryptRoomEvent(event);
    if (decrypted.type == matrix.EventTypes.Encrypted) {
      return null;
    }

    return room.convertEvent(decrypted);
  }
}
