import 'package:commet/client/matrix/components/voip_room/matrix_rtc_stale_membership.dart';
import 'package:flutter_test/flutter_test.dart';

({String? sender, Map<String, dynamic> content}) _m(
        String? sender, Map<String, dynamic> content) =>
    (sender: sender, content: content);

void main() {
  const me = "@me:example.org";

  test('our own device\'s live membership is stale at start', () {
    final keys = MatrixRtcStaleMembership.staleKeys({
      "_@me:example.org_DEV_m.call":
          _m(me, {"device_id": "DEV", "scope": "m.room"}),
    }, userId: me, deviceId: "DEV");
    expect(keys, ["_@me:example.org_DEV_m.call"]);
  });

  test('other devices, other people and cleared memberships are left alone',
      () {
    final keys = MatrixRtcStaleMembership.staleKeys({
      "a": _m(me, {"device_id": "OTHER"}),
      "b": _m("@you:example.org", {"device_id": "DEV"}),
      "c": _m(me, {}),
      "d": _m(null, {"device_id": "DEV"}),
    }, userId: me, deviceId: "DEV");
    expect(keys, isEmpty);
  });
}
