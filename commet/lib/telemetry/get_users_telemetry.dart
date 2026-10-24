import 'package:matrix/matrix.dart' as matrix;

/// Vommet: the loads of rooms' stored members (the SDK's `getUsers(room)`,
/// timed by matrix `GetUsersStats`) in the perf_summary `db` timers, so a
/// slow member load shows up on every platform, the web included (whose
/// store has no database timers). Like the other `db` entries the figures
/// cover the time since the previous summary:
/// - `Get_users_room`: how many loads ran and their total time;
/// - `Get_users_room_max`: the slowest single load, its time as `total_ms`
///   and the number of members it returned as `calls`.
/// Nothing is sent when no load ran.
class GetUsersTelemetry {
  static List<Map<String, Object>> timers([matrix.GetUsersSnapshot? snapshot]) {
    final s = snapshot ?? matrix.GetUsersStats.take();
    if (s.calls <= 0) return const [];
    return [
      {
        "name": "Get_users_room",
        "calls": s.calls.clamp(0, 1000000),
        "total_ms": s.total.inMilliseconds.clamp(0, 86400000),
      },
      {
        "name": "Get_users_room_max",
        "calls": s.worstUsers.clamp(0, 1000000),
        "total_ms": s.worst.inMilliseconds.clamp(0, 86400000),
      },
    ];
  }

  /// [db] (the database timers) followed by these, at most [max] in all.
  static List<Map<String, Object>> appendTo(List<Map<String, Object>> db,
      {int max = 64}) {
    final out = [...db];
    for (final t in timers()) {
      if (out.length >= max) break;
      out.add(t);
    }
    return out;
  }
}
