// Vommet (schema v11): how long the app spends applying each sync response,
// across all accounts. Measured from the SDK's "processing" status to
// "finished": the time between a response arriving and the app being done
// with it (room and event handling plus the database write). Wall time, so
// it includes database waits, not only work on the UI isolate; the loop_lag
// event shows how much of it blocked the UI.
//
// Schema v12 splits that time at the SDK's "cleaningUp" status: "save" is
// the response being applied and written to the database (including any
// wait for startup loads), "followup" what the SDK does before the next
// sync can start: refreshing other users' device keys (a /keys/query that
// can wait on slow remote servers) and sending queued to-device messages.

import 'package:commet/telemetry/frame_stats.dart';
import 'package:commet/telemetry/telemetry.dart';
import 'package:matrix/matrix.dart' as matrix;

class SyncStats {
  static final MsHistogram _apply = MsHistogram();
  static final MsHistogram _save = MsHistogram();
  static final MsHistogram _followup = MsHistogram();
  static int _totalMs = 0;
  static int _followupTotalMs = 0;

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
    int? saveMs;
    return (event) {
      if (!Telemetry.enabled) return;
      switch (event.status) {
        case matrix.SyncStatus.processing:
          saveMs = null;
          clock
            ..reset()
            ..start();
        case matrix.SyncStatus.cleaningUp:
          if (!clock.isRunning || saveMs != null) return;
          saveMs = clock.elapsedMilliseconds;
        case matrix.SyncStatus.finished:
          if (!clock.isRunning) return;
          clock.stop();
          final ms = clock.elapsedMilliseconds;
          _apply.add(ms);
          _totalMs += ms;
          final save = saveMs;
          if (save != null) {
            _save.add(save);
            _followup.add(ms - save);
            _followupTotalMs += ms - save;
          }
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
      if (_save.count > 0) ...{
        "save_p95_ms": _save.p95(),
        "save_worst_ms": _save.worstMs.clamp(0, 86400000),
        "followup_p95_ms": _followup.p95(),
        "followup_worst_ms": _followup.worstMs.clamp(0, 86400000),
        "followup_total_ms": _followupTotalMs.clamp(0, 86400000),
      },
    });
    reset();
  }

  static void reset() {
    _apply.reset();
    _save.reset();
    _followup.reset();
    _totalMs = _followupTotalMs = 0;
  }
}
