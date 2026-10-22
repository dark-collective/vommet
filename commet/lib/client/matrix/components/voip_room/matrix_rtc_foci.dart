/// Vommet (multi-SFU, MSC4195): which LiveKit SFU each call member publishes
/// on, mirroring matrix-js-sdk's `CallMembership.getTransport()`.
///
/// * `oldest_membership` (Commet, Vommet, Element Call before 0.21): everyone
///   publishes on the oldest membership's `foci_preferred[0]`.
/// * `multi_sfu` (Element Call 0.21 and later): every member publishes on its
///   own `foci_preferred[0]`, usually its homeserver's SFU, and listens on
///   everyone else's.
///
/// "Oldest" is by `created_ts`, falling back to `origin_server_ts`; ties break
/// on the state key so every client agrees. Expired memberships never count.
library;

class RtcFocusSelection {
  static const oldestMembership = "oldest_membership";
  static const multiSfu = "multi_sfu";
}

/// One live call membership, reduced to what focus resolution needs.
class RtcMember {
  final String stateKey;
  final String userId;
  final String? deviceId;
  final int createdTs;

  /// `focus_active.focus_selection`, or null if absent / not LiveKit.
  final String? selection;

  /// The first LiveKit entry of `foci_preferred` (its `livekit_service_url`).
  final Uri? preferred;

  const RtcMember({
    required this.stateKey,
    required this.userId,
    required this.deviceId,
    required this.createdTs,
    required this.selection,
    required this.preferred,
  });

  bool get knownSelection =>
      selection == RtcFocusSelection.oldestMembership ||
      selection == RtcFocusSelection.multiSfu;

  /// Parses an `org.matrix.msc3401.call.member` state event. Returns null for
  /// a left (empty), expired, or non-room-call membership.
  static RtcMember? parse({
    required String stateKey,
    required String sender,
    required Map<String, dynamic> content,
    required int originServerTs,
    required int nowMs,
  }) {
    if (content.isEmpty) return null;
    final application = content["application"];
    if (application != null && application != "m.call") return null;
    final scope = content["scope"];
    if (scope != null && scope != "m.room") return null;

    final created = content["created_ts"];
    final createdTs = created is int ? created : originServerTs;
    final expires = content["expires"];
    if (expires is int && createdTs + expires <= nowMs) return null;

    final active = content["focus_active"];
    String? selection;
    if (active is Map && active["type"] == "livekit") {
      final s = active["focus_selection"];
      if (s is String) selection = s;
    }

    Uri? preferred;
    final foci = content["foci_preferred"];
    if (foci is List) {
      for (final f in foci) {
        if (f is! Map || f["type"] != "livekit") continue;
        final url = f["livekit_service_url"];
        if (url is! String) continue;
        preferred = normalize(Uri.tryParse(url));
        if (preferred != null) break;
      }
    }

    final device = content["device_id"];
    return RtcMember(
      stateKey: stateKey,
      userId: sender,
      deviceId: device is String ? device : null,
      createdTs: createdTs,
      selection: selection,
      preferred: preferred,
    );
  }

  /// Two memberships naming the same lk-jwt service compare equal even with
  /// a trailing slash or different case in the host.
  static Uri? normalize(Uri? uri) {
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
    var path = uri.path;
    while (path.endsWith("/")) {
      path = path.substring(0, path.length - 1);
    }
    return Uri(
        scheme: uri.scheme.toLowerCase(),
        host: uri.host.toLowerCase(),
        port: uri.hasPort ? uri.port : null,
        path: path);
  }
}

class RtcFoci {
  static RtcMember? oldest(Iterable<RtcMember> members) {
    RtcMember? best;
    for (final m in members) {
      if (best == null ||
          m.createdTs < best.createdTs ||
          (m.createdTs == best.createdTs &&
              m.stateKey.compareTo(best.stateKey) < 0)) {
        best = m;
      }
    }
    return best;
  }

  /// The call's elected SFU: the one the oldest member publishes on, and the
  /// only one a legacy (`oldest_membership`) client listens on. That's where
  /// we publish, so both legacy clients and Element Call find us.
  static Uri? elected(Iterable<RtcMember> members) {
    final o = oldest(members);
    if (o == null || !o.knownSelection) return null;
    return o.preferred;
  }

  /// Where [member] publishes, by its own selection.
  static Uri? transportOf(RtcMember member, Iterable<RtcMember> members) {
    return switch (member.selection) {
      RtcFocusSelection.multiSfu => member.preferred,
      RtcFocusSelection.oldestMembership => elected(members),
      _ => null,
    };
  }

  /// Every SFU someone other than us may be publishing on: each member's
  /// resolved transport, plus each member's own `foci_preferred[0]`, because a
  /// legacy client that didn't understand the election (Commet skips
  /// `multi_sfu` members) falls back to its own SFU.
  static Set<Uri> remoteTransports(
      Iterable<RtcMember> members, bool Function(RtcMember) isSelf) {
    final all = members.toList();
    final result = <Uri>{};
    for (final m in all) {
      if (isSelf(m)) continue;
      final t = transportOf(m, all);
      if (t != null) result.add(t);
      if (m.preferred != null) result.add(m.preferred!);
    }
    return result;
  }
}
