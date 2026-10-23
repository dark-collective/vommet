import 'package:commet/client/matrix/components/room_call/matrix_room_call_component.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final sent = DateTime.utc(2026, 10, 7, 20);
  final now = sent.add(const Duration(hours: 1));
  bool live(Map<String, dynamic> content) =>
      MatrixRoomCallComponent.isLiveMembership(content, sent, now);

  test('an Element Call membership is live', () {
    expect(
        live({
          "application": "m.call",
          "call_id": "",
          "scope": "m.room",
          "device_id": "ABC",
          "expires": 14400000,
        }),
        isTrue);
  });

  test('a left (empty) membership is not', () {
    expect(live({}), isFalse);
  });

  test('an expired membership is not', () {
    expect(live({"application": "m.call", "expires": 1800000}), isFalse);
  });

  test('other applications and scopes are not calls in this room', () {
    expect(live({"application": "m.game"}), isFalse);
    expect(live({"application": "m.call", "scope": "m.user"}), isFalse);
  });

  test('a membership without expires stays live', () {
    expect(live({"application": "m.call"}), isTrue);
  });

  group('ringing (MSC4075)', () {
    final at = DateTime.utc(2026, 10, 8, 1);
    Duration? ring(String type, Map<String, dynamic> content,
            {String sender = "@them:a", DateTime? now}) =>
        MatrixRoomCallComponent.ringDuration(
            type: type,
            content: content,
            sender: sender,
            self: "@me:a",
            sent: at,
            now: now ?? at.add(const Duration(seconds: 2)));

    test('call.notify ring rings for the rest of 30 s', () {
      expect(ring("org.matrix.msc4075.call.notify", {"notify_type": "ring"}),
          const Duration(seconds: 28));
    });

    test('rtc.notification uses sender_ts and lifetime', () {
      expect(
          ring("org.matrix.msc4075.rtc.notification", {
            "notification_type": "ring",
            "sender_ts": at.millisecondsSinceEpoch,
            "lifetime": 10000,
          }),
          const Duration(seconds: 8));
    });

    test('notify (group), our own, and old notifications do not ring', () {
      expect(ring("org.matrix.msc4075.call.notify", {"notify_type": "notify"}),
          isNull);
      expect(
          ring("org.matrix.msc4075.call.notify", {"notify_type": "ring"},
              sender: "@me:a"),
          isNull);
      expect(
          ring("org.matrix.msc4075.call.notify", {"notify_type": "ring"},
              now: at.add(const Duration(minutes: 1))),
          isNull);
      expect(ring("m.room.message", {"notify_type": "ring"}), isNull);
    });
  });
}
