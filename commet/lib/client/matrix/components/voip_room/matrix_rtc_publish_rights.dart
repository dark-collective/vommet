import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart' as mx;

/// Vommet: whether we may speak on an SFU.
///
/// lk-jwt-service 0.7 and later gives users from homeservers it doesn't serve
/// a listen-only LiveKit token (`canPublish: false`). Joining a call whose
/// elected SFU belongs to another homeserver then hears everyone, but every
/// unmute is ignored by the SFU and times out after 10 s
/// (`TrackPublishException`), we have no tile and aren't counted. The way
/// out is the MSC4195 one: publish on our own homeserver's SFU
/// (`multi_sfu`) and listen on the elected one.
class MatrixRtcPublishRights {
  /// The `video.canPublish` grant of a LiveKit [jwt]. LiveKit treats a
  /// missing grant as allowed, and so do we for a token we can't read.
  static bool canPublish(String jwt) {
    try {
      final parts = jwt.split(".");
      if (parts.length < 2) return true;
      final payload = jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      if (payload is! Map) return true;
      final video = payload["video"];
      if (video is! Map) return true;
      return video["canPublish"] != false;
    } catch (_) {
      return true;
    }
  }

  /// A LiveKit url + token for [focus] (legacy `/sfu/get`, as join uses).
  static Future<({String url, String jwt})> fetch(
      mx.Room room, Uri focus) async {
    if (focus.scheme != "https") {
      throw Exception("Focus $focus does not use HTTPS");
    }
    final token = await room.client.requestOpenIdToken(room.client.userID!, {});
    final result = await http.post(Uri.parse("$focus/sfu/get"),
        body: jsonEncode({
          "device_id": room.client.deviceID!,
          "room": room.id,
          "openid_token": {
            "matrix_server_name": token.matrixServerName,
            "access_token": token.accessToken,
            "expires_in": token.expiresIn,
          }
        }));
    if (result.statusCode != 200) {
      throw Exception("lk-jwt HTTP ${result.statusCode}");
    }
    final data = jsonDecode(result.body) as Map<String, dynamic>;
    return (url: data["url"] as String, jwt: data["jwt"] as String);
  }
}
