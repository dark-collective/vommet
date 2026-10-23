/// Vommet: the lifetime of our own `org.matrix.msc3401.call.member` state,
/// mirroring matrix-js-sdk's `MembershipManager` (what Element Call and
/// Element X run).
///
/// A membership is valid until `created_ts + expires`, where `created_ts`
/// falls back to the event's own `origin_server_ts`. The first post carries
/// no `created_ts` (the server's timestamp counts, so a skewed clock can't
/// claim to be the oldest member); every later post of the same membership
/// inherits it, so other clients keep seeing one membership (js-sdk keys its
/// media-key sharing on `created_ts`: a changed value looks like a new
/// member and re-shares keys with everyone) and the election order doesn't
/// move. `expires` grows by one lifetime per refresh, so the absolute expiry
/// keeps moving out while we're in the call.
library;

class MatrixRtcMembership {
  /// How long one post keeps a membership alive: 4 hours, js-sdk's default.
  static const expiresMs = 4 * 60 * 60 * 1000;

  /// How often we re-post: js-sdk refreshes every
  /// `min(expires, 60 minutes)`.
  static const refreshEveryMs = 60 * 60 * 1000;

  /// Re-post this long before the refresh is due.
  static const headroomMs = 5 * 1000;

  /// `created_ts`, falling back to the event's `origin_server_ts`.
  static int createdTs(Map<String, dynamic> content, int originServerTs) {
    final created = content["created_ts"];
    return created is int ? created : originServerTs;
  }

  /// The membership's absolute expiry in ms, or null if it never expires.
  static int? absoluteExpiry(Map<String, dynamic> content, int originServerTs) {
    final expires = content["expires"];
    if (expires is! int) return null;
    return createdTs(content, originServerTs) + expires;
  }

  /// A membership counts while it has content, is for a room-wide `m.call`,
  /// and hasn't passed its `expires` (a crashed client leaves its membership
  /// behind, and the chat would otherwise show a call that isn't there).
  static bool isLive(
      Map<String, dynamic> content, int originServerTs, int nowMs) {
    if (content.isEmpty) return false;
    final application = content["application"];
    if (application != null && application != "m.call") return false;
    final scope = content["scope"];
    if (scope != null && scope != "m.room") return false;
    final expiry = absoluteExpiry(content, originServerTs);
    return expiry == null || expiry > nowMs;
  }

  /// The content to re-post for our membership [current] (sent at
  /// [originServerTs]) on its [iteration]th refresh (the first post is
  /// iteration 1, so the first refresh is 2). Everything else in the
  /// membership (foci, focus selection, device) is kept as it is.
  static Map<String, dynamic> refreshed(
      Map<String, dynamic> current, int originServerTs, int iteration) {
    final content = Map<String, dynamic>.from(current);
    content["created_ts"] = createdTs(current, originServerTs);
    content["expires"] = expiresMs * iteration;
    return content;
  }

  /// When (ms) the [iteration]th post is due, for a membership first posted
  /// at [startMs]: js-sdk's `computeNextExpiryActionTs`.
  static int refreshDueAt(int startMs, int iteration) =>
      startMs + refreshEveryMs * (iteration - 1) - headroomMs;
}
