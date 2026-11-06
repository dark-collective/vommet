import 'dart:convert';

import 'package:commet/client/matrix/components/voip_room/matrix_rtc_publish_rights.dart';
import 'package:flutter_test/flutter_test.dart';

String _jwt(Map<String, dynamic> payload) {
  String part(Object o) =>
      base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll("=", "");
  return "${part({"alg": "HS256", "typ": "JWT"})}.${part(payload)}.sig";
}

void main() {
  test("a listen-only lk-jwt token can't publish", () {
    expect(
        MatrixRtcPublishRights.canPublish(_jwt({
          "sub": "@a:example.org:DEV",
          "video": {"roomJoin": true, "canPublish": false, "canSubscribe": true}
        })),
        isFalse);
  });

  test("a full-access token can publish", () {
    expect(
        MatrixRtcPublishRights.canPublish(_jwt({
          "video": {"roomJoin": true, "canPublish": true}
        })),
        isTrue);
  });

  test("a missing grant counts as allowed, as LiveKit does", () {
    expect(
        MatrixRtcPublishRights.canPublish(_jwt({
          "video": {"roomJoin": true}
        })),
        isTrue);
    expect(MatrixRtcPublishRights.canPublish(_jwt({"sub": "x"})), isTrue);
  });

  test("an unreadable token counts as allowed", () {
    expect(MatrixRtcPublishRights.canPublish("not a jwt"), isTrue);
    expect(MatrixRtcPublishRights.canPublish("a.%%%.c"), isTrue);
  });
}
