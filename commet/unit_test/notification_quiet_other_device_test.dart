import 'package:commet/client/components/push_notification/modifiers/suppress_other_device_active.dart';
import 'package:matrix/matrix.dart' show Device, MatrixEvent;
import 'package:test/test.dart';

typedef Rule = NotificationModifierSuppressOtherActiveDevice;

final now = DateTime(2026, 10, 8, 20, 0);

Device device(String id, Duration? ago) => Device(
    deviceId: id,
    lastSeenTs: ago == null ? null : now.subtract(ago).millisecondsSinceEpoch);

MatrixEvent event(String sender, Duration ago,
        {String? stateKey, String type = "m.room.message"}) =>
    MatrixEvent(
        type: stateKey == null ? type : "m.room.member",
        content: const {},
        senderId: sender,
        eventId: "\$${sender.hashCode}${ago.inSeconds}",
        originServerTs: now.subtract(ago),
        stateKey: stateKey);

void main() {
  group("otherDeviceOnline", () {
    test("ignores this device", () {
      expect(
          Rule.otherDeviceOnline(
              [device("PHONE", Duration.zero)], "PHONE", now),
          false);
    });
    test("another device seen 3 minutes ago counts", () {
      expect(
          Rule.otherDeviceOnline([
            device("PHONE", Duration.zero),
            device("DESKTOP", const Duration(minutes: 3)),
          ], "PHONE", now),
          true);
    });
    test("another device seen 10 minutes ago doesn't", () {
      expect(
          Rule.otherDeviceOnline(
              [device("DESKTOP", const Duration(minutes: 10))], "PHONE", now),
          false);
    });
    test("a device never seen doesn't", () {
      expect(
          Rule.otherDeviceOnline([device("OLD", null)], "PHONE", now), false);
    });
  });

  group("lastOwnEvent", () {
    const me = "@me:example.org";
    test("your message 2 minutes ago counts", () {
      final mine = event(me, const Duration(minutes: 2));
      expect(
          Rule.lastOwnEvent(
              [event("@friend:example.org", Duration.zero), mine], me, now),
          mine);
    });
    test("your reaction counts", () {
      final mine = event(me, const Duration(minutes: 1), type: "m.reaction");
      expect(Rule.lastOwnEvent([mine], me, now), mine);
    });
    test("your message 20 minutes ago doesn't", () {
      expect(
          Rule.lastOwnEvent([event(me, const Duration(minutes: 20))], me, now),
          null);
    });
    test("only others talking doesn't", () {
      expect(
          Rule.lastOwnEvent(
              [event("@friend:example.org", Duration.zero)], me, now),
          null);
    });
    test("your own state change (e.g. joining) doesn't", () {
      expect(
          Rule.lastOwnEvent(
              [event(me, const Duration(minutes: 1), stateKey: me)], me, now),
          null);
    });
    test("other event types (e.g. a call ringing) don't", () {
      expect(
          Rule.lastOwnEvent([
            event(me, const Duration(minutes: 1),
                type: "org.matrix.msc4075.rtc.notification")
          ], me, now),
          null);
    });
  });

  group("sentElsewhere", () {
    final mine = event("@me:example.org", const Duration(minutes: 1));
    test("not recorded as sent here: from another device", () {
      expect(Rule.sentElsewhere(mine, {r"$other"}), true);
    });
    test("recorded as sent here: from this device", () {
      expect(Rule.sentElsewhere(mine, {mine.eventId}), false);
    });
  });
}
