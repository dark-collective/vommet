import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart';

/// Vommet: which session (device) a push registration belongs to.
///
/// Homeservers delete a session's pushers when it signs out (Tuwunel and
/// Synapse both do), so a stale pusher belongs to a session that is still
/// signed in but no longer used. The pusher list doesn't say which session
/// registered each pusher, so Vommet records its device id in its pushers'
/// data ([deviceIdKey]); other apps' pushers can only be matched by name.
class PusherSession {
  const PusherSession(this.device, {required this.exact});

  final Device device;

  /// True when the pusher names its session; false for a name match.
  final bool exact;

  DateTime? get lastSeen => device.lastSeenTs == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(device.lastSeenTs!);
}

class PusherHousekeeping {
  /// Vommet's pushers carry the Matrix device id that registered them.
  /// Namespaced: Commet registers under the same app id, and a pusher
  /// without this key is never removed automatically.
  static const String deviceIdKey = "im.nether.vommet.device_id";

  /// Vommet and Commet register under the same app id.
  static const Set<String> ourAppIds = {"chat.commet.commetapp.android"};

  /// Commet's own gateway; its pushes reach the Commet app only (through
  /// Commet's Firebase project), so such a pusher is Commet's, not ours.
  static const String commetGatewayHost = "push.commet.chat";

  /// A session unused for this long no longer gets our pushes. If it comes
  /// back, Vommet registers it again at startup.
  static const Duration staleAfter = Duration(days: 90);

  static String? taggedDeviceId(Pusher pusher) {
    final id = pusher.data.additionalProperties[deviceIdKey];
    return id is String ? id : null;
  }

  static String? gatewayHost(Pusher pusher) => pusher.data.url?.host;

  static bool usesCommetGateway(Pusher pusher) =>
      gatewayHost(pusher) == commetGatewayHost;

  /// The session [pusher] belongs to: exact when it names its device,
  /// otherwise the one session whose name matches, if exactly one does.
  static PusherSession? sessionOf(Pusher pusher, List<Device> devices) {
    final tagged = taggedDeviceId(pusher);
    if (tagged != null) {
      final device = devices.firstWhereOrNull((d) => d.deviceId == tagged);
      return device == null ? null : PusherSession(device, exact: true);
    }

    final named =
        devices.where((d) => d.displayName == pusher.deviceDisplayName);
    return named.length == 1 ? PusherSession(named.single, exact: false) : null;
  }

  /// Our pushers to delete automatically: ones that name their session,
  /// when that session is gone or hasn't been seen for [staleAfter]. Never
  /// [ownDeviceId]'s, and never one whose session is unknown (untagged
  /// pushers and other apps' are left to the person).
  static bool isStale(Pusher pusher, List<Device> devices, DateTime now,
      {required String? ownDeviceId}) {
    if (!ourAppIds.contains(pusher.appId)) return false;
    final tagged = taggedDeviceId(pusher);
    if (tagged == null || tagged == ownDeviceId) return false;

    final device = devices.firstWhereOrNull((d) => d.deviceId == tagged);
    if (device == null) return true;
    final lastSeen = device.lastSeenTs;
    if (lastSeen == null) return false;
    return now.difference(DateTime.fromMillisecondsSinceEpoch(lastSeen)) >
        staleAfter;
  }

  /// "active today", "last active 3 days ago", "last active 4 months ago".
  static String lastActive(DateTime? seen, DateTime now) {
    if (seen == null) return "last activity unknown";
    final days = now.difference(seen).inDays;
    if (days < 1) return "active today";
    if (days == 1) return "last active yesterday";
    if (days < 31) return "last active $days days ago";
    final months = days ~/ 30;
    if (months < 12) {
      return "last active $months month${months == 1 ? "" : "s"} ago";
    }
    final years = days ~/ 365;
    return "last active $years year${years == 1 ? "" : "s"} ago";
  }
}
