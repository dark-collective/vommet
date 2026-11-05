import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Vommet: the Matrix user behind a LiveKit participant identity.
///
/// The legacy lk-jwt `/sfu/get` gives `@user:server:DEVICE`, so the user id
/// was taken as the first two `:` parts. lk-jwt-service 0.6+ gives Element
/// Call's newer joins an opaque identity instead: unpadded base64 of the
/// SHA-256 of a JSON array (`[user, member id]`, or `[user, device, member
/// id]` on its legacy endpoint). Splitting that threw a RangeError ("Not in
/// inclusive range 0..1: 2"), so such a participant's tracks never got a tile
/// and the voice room list drew an error box. We match it against the call's
/// memberships, and fall back to the identity itself.
class LivekitIdentity {
  /// [members]: the call's memberships, as (sender, content, state key).
  static String userId(String identity,
      [Iterable<
              ({String sender, Map<String, dynamic> content, String stateKey})>
          members = const []]) {
    final parts = identity.split(":");
    if (identity.startsWith("@") && parts.length >= 2) {
      return parts.take(2).join(":");
    }
    for (final m in members) {
      if (_candidates(m.sender, m.content, m.stateKey).contains(identity)) {
        return m.sender;
      }
    }
    return identity;
  }

  /// Vommet: the call membership behind [identity], or null when it has
  /// none (a LiveKit-only participant, or one whose membership left).
  static ({
    String sender,
    Map<String, dynamic> content,
    String stateKey
  })? membership(
      String identity,
      Iterable<({String sender, Map<String, dynamic> content, String stateKey})>
          members) {
    final parts = identity.split(":");
    final legacy = identity.startsWith("@") && parts.length >= 2;
    final user = legacy ? parts.take(2).join(":") : null;
    final device = legacy && parts.length >= 3 ? parts.skip(2).join(":") : null;
    for (final m in members) {
      if (m.content.isEmpty) continue;
      if (legacy) {
        if (m.sender != user) continue;
        final d = m.content["device_id"];
        if (device == null || d == device || m.stateKey.contains(device)) {
          return m;
        }
        continue;
      }
      if (_candidates(m.sender, m.content, m.stateKey).contains(identity)) {
        return m;
      }
    }
    return null;
  }

  /// Vommet: the Matrix device behind [identity]: the legacy identity's
  /// third part, else its membership's `device_id`.
  static String? deviceId(
      String identity,
      Iterable<({String sender, Map<String, dynamic> content, String stateKey})>
          members) {
    final parts = identity.split(":");
    if (identity.startsWith("@") && parts.length >= 3) {
      return parts.skip(2).join(":");
    }
    final d = membership(identity, members)?.content["device_id"];
    return d is String ? d : null;
  }

  /// lk-jwt-service's identity hash of [parts].
  static String hash(List<String> parts) => base64
      .encode(sha256.convert(utf8.encode(jsonEncode(parts))).bytes)
      .replaceAll("=", "");

  static Iterable<String> _candidates(
      String sender, Map<String, dynamic> content, String stateKey) sync* {
    final device = content["device_id"];
    final member = content["member"];
    final ids = <String>{
      stateKey,
      if (content["membershipID"] is String) content["membershipID"] as String,
      if (content["member_id"] is String) content["member_id"] as String,
      if (member is Map && member["id"] is String) member["id"] as String,
      if (device is String) "$sender:$device",
    };
    for (final id in ids) {
      yield hash([sender, id]);
      if (device is String) yield hash([sender, device, id]);
    }
  }
}
