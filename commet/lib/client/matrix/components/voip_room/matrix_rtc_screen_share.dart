import 'dart:math';
import 'package:commet/client/matrix/components/voip_room/matrix_rtc_membership.dart';
import 'package:matrix/matrix.dart';

class MatrixRtcScreenShare {
  static const field = 'im.nether.screenshare';

  /// Only attribute an advertisement to its sender's own device membership.
  /// No identity or display name inside the extension is trusted.
  static int? expiry({
    required Map<String, dynamic> content,
    required String sender,
    required String? stateKey,
    required int originServerTs,
    required int nowMs,
  }) {
    final device = content['device_id'];
    if (device is! String ||
        device.isEmpty ||
        stateKey != '_${sender}_${device}_m.call' ||
        content['application'] != 'm.call' ||
        content['scope'] != 'm.room' ||
        content['call_id'] != '') return null;
    if (content.containsKey('created_ts') && content['created_ts'] is! int)
      return null;
    final expires = content['expires'];
    final created = MatrixRtcMembership.createdTs(content, originServerTs);
    if (originServerTs < 0 ||
        originServerTs > nowMs + 300000 ||
        expires is! int ||
        expires <= 0 ||
        created < 0 ||
        !MatrixRtcMembership.isLive(content, originServerTs, nowMs))
      return null;
    final share = content[field];
    if (share is! Map || share['active'] != true) return null;
    if (share['since'] is! int) return null;
    final membershipExpiry =
        MatrixRtcMembership.absoluteExpiry(content, originServerTs)!;
    // The legacy refresh's relative expires grows over long calls. Discovery
    // must still age out within four hours of the latest membership report.
    // Hourly refreshes retain the extension while the sharer is running.
    final reportExpiry = originServerTs + MatrixRtcMembership.expiresMs;
    final until = min(membershipExpiry, reportExpiry);
    return until > nowMs ? until : null;
  }

  static Map<String, int> reports(Room room) {
    if (room.membership != Membership.join) return {};
    final events = room.states['org.matrix.msc3401.call.member']?.values
            .whereType<Event>() ??
        const <Event>[];
    return collect(events.where((event) {
      // Lazy-loaded users may be unknown; a known leave/ban is decisive.
      final membership = room
          .getState(EventTypes.RoomMember, event.senderId)
          ?.content['membership'];
      return membership == null || membership == 'join';
    }));
  }

  static Map<String, int> collect(Iterable<Event> events, {int? nowMs}) {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final result = <String, int>{};
    for (final e in events) {
      final until = expiry(
          content: e.content,
          sender: e.senderId,
          stateKey: e.stateKey,
          originServerTs: e.originServerTs.millisecondsSinceEpoch,
          nowMs: now);
      if (until != null && until > (result[e.senderId] ?? 0)) {
        result[e.senderId] = until;
      }
    }
    return result;
  }
}
