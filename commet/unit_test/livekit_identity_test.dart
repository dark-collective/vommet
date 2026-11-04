import 'package:commet/client/matrix/components/voip_room/livekit_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("a legacy identity gives the user id", () {
    expect(LivekitIdentity.userId("@a:example.org:DEVICE"), "@a:example.org");
  });

  test("an opaque identity without memberships doesn't throw", () {
    expect(LivekitIdentity.userId("q83vEjRWeJA"), "q83vEjRWeJA");
    expect(LivekitIdentity.userId(""), "");
  });

  test("the hash matches lk-jwt-service (unpadded base64 sha256 of JSON)", () {
    // sha256('["@a:b","m"]') in unpadded standard base64.
    expect(LivekitIdentity.hash(["@a:b", "m"]),
        "7baSVLW/xgffzUOKSzZM7fb+1oi+e/3tDpt/5uckke8");
  });

  test("an opaque identity is matched against the call's memberships", () {
    final content = <String, dynamic>{
      "device_id": "DEV",
      "membershipID": "member-1",
    };
    final identity = LivekitIdentity.hash(["@b:example.org", "member-1"]);
    expect(
        LivekitIdentity.userId(identity, [
          (
            sender: "@c:example.org",
            content: <String, dynamic>{},
            stateKey: "x"
          ),
          (sender: "@b:example.org", content: content, stateKey: "y"),
        ]),
        "@b:example.org");
    final legacy = LivekitIdentity.hash(["@b:example.org", "DEV", "member-1"]);
    expect(
        LivekitIdentity.userId(legacy, [
          (sender: "@b:example.org", content: content, stateKey: "y"),
        ]),
        "@b:example.org");
  });
}
