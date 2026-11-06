import 'package:commet/client/components/push_notification/android/read_elsewhere.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;

// Vommet issue 808: which notified rooms the server's /notifications list
// says were read on another device.
void main() {
  const a = "!a:example.org";
  const b = "!b:example.org";
  const c = "!c:example.org";

  matrix.Notification notification(String roomId, bool read, int n) =>
      matrix.Notification(
        actions: const ["notify"],
        event: matrix.MatrixEvent(
          type: matrix.EventTypes.Message,
          content: const {"body": "hi"},
          senderId: "@alice:example.org",
          eventId: "\$$n",
          originServerTs: DateTime(2026, 10, 27),
          roomId: roomId,
        ),
        read: read,
        roomId: roomId,
        ts: n,
      );

  test("a room whose notifications are all read counts as read", () {
    final list = [notification(a, true, 2), notification(a, true, 1)];
    expect(ReadElsewhere.readRooms(list, {a}), {a});
  });

  test("a room with any unread notification stays", () {
    final list = [notification(a, false, 2), notification(a, true, 1)];
    expect(ReadElsewhere.readRooms(list, {a}), isEmpty);
  });

  test("rooms missing from the list are left alone", () {
    final list = [notification(a, true, 1)];
    expect(ReadElsewhere.readRooms(list, {a, b}), {a});
  });

  test("rooms not on screen are ignored", () {
    final list = [notification(c, true, 1), notification(b, false, 2)];
    expect(ReadElsewhere.readRooms(list, {a, b}), isEmpty);
  });
}
