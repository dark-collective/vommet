import 'package:commet/debug/log.dart';
import 'package:matrix/matrix.dart' as matrix;

/// Vommet: clears "mark as unread" (m.marked_unread, or FluffyChat's
/// com.famedly.marked_unread) once the room is read, as MSC2867 asks. The
/// flag is room account data, so it survives restarts; set from another
/// client, it kept the room's unread dot lit after reading everything
/// (Vommet issue 366). The SDK's read marker doesn't touch it.
Future<void> clearMarkedUnread(matrix.Room room) async {
  if (!room.markedUnread || room.membership != matrix.Membership.join) return;
  try {
    await room.markUnread(false);
  } catch (e, s) {
    Log.onError(e, s, content: "Couldn't clear the room's unread mark");
  }
}
