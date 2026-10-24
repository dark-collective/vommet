import 'package:commet/client/matrix/components/push_notifications/pusher_housekeeping.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

Pusher pusher(
        {String appId = "chat.commet.commetapp.android",
        String device = "local-1",
        String gateway =
            "https://matrix.gateway.unifiedpush.org/_matrix/push/v1/notify",
        String? deviceId}) =>
    Pusher(
      appId: appId,
      pushkey: "https://ntfy.example/up$device",
      appDisplayName: "Vommet",
      data: PusherData(
        url: Uri.parse(gateway),
        additionalProperties: {
          if (deviceId != null) PusherHousekeeping.deviceIdKey: deviceId
        },
      ),
      deviceDisplayName: device,
      kind: "http",
      lang: "en",
    );

final now = DateTime(2026, 10, 8);
int daysAgo(int d) => now.subtract(Duration(days: d)).millisecondsSinceEpoch;

void main() {
  final devices = [
    Device(deviceId: "PHONE", displayName: "Vommet", lastSeenTs: daysAgo(0)),
    Device(deviceId: "OLDTAB", displayName: "Vommet", lastSeenTs: daysAgo(200)),
    Device(
        deviceId: "LAPTOP",
        displayName: "Element Desktop",
        lastSeenTs: daysAgo(3)),
  ];

  group("isStale", () {
    bool stale(Pusher p) =>
        PusherHousekeeping.isStale(p, devices, now, ownDeviceId: "PHONE");

    test("our pusher of a session unused for 90+ days", () {
      expect(stale(pusher(deviceId: "OLDTAB")), isTrue);
    });
    test("our pusher of a signed-out session", () {
      expect(stale(pusher(deviceId: "GONE")), isTrue);
    });
    test("kept: recently used session, our own device, untagged", () {
      expect(stale(pusher(deviceId: "LAPTOP")), isFalse);
      expect(stale(pusher(deviceId: "PHONE")), isFalse);
      expect(stale(pusher()), isFalse);
    });
    test("kept: a Commet pusher (same app id), even naming an old device", () {
      // Commet registers under our app id; only our namespaced key counts.
      final commet = Pusher(
        appId: "chat.commet.commetapp.android",
        pushkey: "commet-fcm-token",
        appDisplayName: "Commet",
        data: PusherData(
          url: Uri.parse("https://push.commet.chat/_matrix/push/v1/notify"),
          additionalProperties: {"device_id": "OLDTAB"},
        ),
        deviceDisplayName: "a1b2c3d4e5f6g7h8i9j0",
        kind: "http",
        lang: "en",
      );
      expect(stale(commet), isFalse);
    });
    test("kept: another app's pusher, even for an old session", () {
      expect(
          stale(pusher(appId: "im.vector.app", deviceId: "OLDTAB")), isFalse);
    });
  });

  group("sessionOf", () {
    test("exact when the pusher names its device", () {
      final s =
          PusherHousekeeping.sessionOf(pusher(deviceId: "LAPTOP"), devices);
      expect(s?.device.deviceId, "LAPTOP");
      expect(s?.exact, isTrue);
    });
    test("probable when exactly one session has the pusher's name", () {
      final s = PusherHousekeeping.sessionOf(
          pusher(device: "Element Desktop"), devices);
      expect(s?.device.deviceId, "LAPTOP");
      expect(s?.exact, isFalse);
    });
    test("unknown when no or several sessions match", () {
      expect(
          PusherHousekeeping.sessionOf(pusher(device: "x"), devices), isNull);
      expect(PusherHousekeeping.sessionOf(pusher(device: "Vommet"), devices),
          isNull);
    });
  });

  test("the old Commet push server is recognised", () {
    expect(
        PusherHousekeeping.usesCommetGateway(
            pusher(gateway: "https://push.commet.chat/_matrix/push/v1/notify")),
        isTrue);
    expect(PusherHousekeeping.usesCommetGateway(pusher()), isFalse);
  });

  test("lastActive", () {
    DateTime ago(int d) => now.subtract(Duration(days: d));
    expect(PusherHousekeeping.lastActive(null, now), "last activity unknown");
    expect(PusherHousekeeping.lastActive(ago(0), now), "active today");
    expect(PusherHousekeeping.lastActive(ago(1), now), "last active yesterday");
    expect(
        PusherHousekeeping.lastActive(ago(12), now), "last active 12 days ago");
    expect(
        PusherHousekeeping.lastActive(ago(40), now), "last active 1 month ago");
    expect(PusherHousekeeping.lastActive(ago(200), now),
        "last active 6 months ago");
    expect(PusherHousekeeping.lastActive(ago(800), now),
        "last active 2 years ago");
  });
}
