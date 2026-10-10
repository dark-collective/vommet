// Vommet (schema v11): how long the app spends applying each sync response,
// across all accounts. Measured from the SDK's "processing" status to
// "finished": the time between a response arriving and the app being done
// with it (room and event handling plus the database write). Wall time, so
// it includes database waits, not only work on the UI isolate; the loop_lag
// event shows how much of it blocked the UI.

import 'package:commet/telemetry/frame_stats.dart';
import 'package:commet/telemetry/telemetry.dart';
import 'package:matrix/matrix.dart' as matrix;

class SyncStats {
  static final MsHistogram _apply = MsHistogram();
  static int _totalMs = 0;

  /// The server name whose accounts count as "own server" in telemetry.
  /// Fixed at build time on purpose, so `own_server: true` always means the
  /// same thing; the name itself is never sent.
  static const ownServerName = "nether.im";

  /// Whether [userId] is an account on [ownServerName]; null when unknown.
  static bool? onOwnServer(String? userId) {
    if (userId == null) return null;
    final colon = userId.indexOf(":");
    if (colon < 0) return null;
    return userId.substring(colon + 1).toLowerCase() == ownServerName;
  }

  /// A listener for one account's sync status stream.
  static void Function(matrix.SyncStatusUpdate) listener() {
    final clock = Stopwatch();
    return (event) {
      if (!Telemetry.enabled) return;
      switch (event.status) {
        case matrix.SyncStatus.processing:
          clock
            ..reset()
            ..start();
        case matrix.SyncStatus.finished:
          if (!clock.isRunning) return;
          clock.stop();
          final ms = clock.elapsedMilliseconds;
          _apply.add(ms);
          _totalMs += ms;
        case matrix.SyncStatus.error:
          clock.stop();
        default:
          return;
      }
    };
  }

  static void report() {
    if (_apply.count == 0) return;
    Telemetry.record("sync_stats", {
      "syncs": _apply.count.clamp(0, 1000000),
      "apply_p95_ms": _apply.p95(),
      "apply_worst_ms": _apply.worstMs.clamp(0, 86400000),
      "apply_total_ms": _totalMs.clamp(0, 86400000),
    });
    reset();
  }

  static void reset() {
    _apply.reset();
    _totalMs = 0;
  }
}
