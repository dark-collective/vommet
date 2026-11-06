import 'package:commet/diagnostic/diagnostics.dart';
import 'package:commet/telemetry/telemetry.dart';
import 'package:matrix/matrix.dart' as matrix;

/// Vommet: the SDK's `Client.init` steps (matrix `InitTimings`) in the
/// app_ready `startup` timers, so a slow `Matrix_client_init` can be broken
/// down on every platform, the web included (whose store has no database
/// timers). Each step is a fixed `Init_` identifier with its duration and a
/// count (how often it ran, or how many rooms, users, keys or events a loop
/// handled); with several accounts the steps are summed.
class InitTimingsTelemetry {
  static final _name = RegExp(r"^Init_[a-z_]{1,58}$");

  /// The schema's limit for one timers list.
  static const maxTimers = 64;

  static List<Map<String, Object>> initTimers(
      Iterable<matrix.InitTiming> spans) {
    final out = <Map<String, Object>>[];
    for (final s in spans) {
      if (!_name.hasMatch(s.name)) continue;
      out.add(<String, Object>{
        "name": s.name,
        "calls": s.calls.clamp(0, 1000000),
        "total_ms": s.elapsed.inMilliseconds.clamp(0, 86400000),
      });
    }
    return out;
  }

  /// The app's startup timers followed by the init steps, at most
  /// [maxTimers] in all.
  static List<Map<String, Object>> startupTimers({
    CumulativeDiagnostics? general,
    Iterable<matrix.InitTiming>? spans,
  }) {
    final out = Telemetry.timers(general ?? Diagnostics.general);
    for (final t in initTimers(spans ?? matrix.InitTimings.spans)) {
      if (out.length >= maxTimers) break;
      out.add(t);
    }
    return out;
  }
}
