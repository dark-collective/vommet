// Vommet (schema v30): how long unlocking an existing account's messages on a
// new device takes (`secure_unlock`), and the background import of the key
// backup that follows (`history_keys_import`). Timings, a fixed path name, a
// failure kind and a key count only: never key material, rooms or ids.

import 'package:commet/telemetry/telemetry.dart';
import 'package:commet/telemetry/telemetry_errors.dart';
import 'package:commet/ui/pages/secure_setup/secure_setup_controller.dart';

/// The step times of one unlock with a recovery key, phrase or password.
class UnlockSteps {
  int? openMs;
  int? cacheMs;
  int? selfSignMs;
}

class SecureUnlockTelemetry {
  /// `secure_unlock` fields: [path] is recovery_key, passphrase or approval;
  /// [screenMs] how long the working screen was up; [error] when it failed.
  static Map<String, Object?> unlockFields(
      {required String path,
      required int screenMs,
      UnlockSteps? steps,
      int? finishMs,
      Object? error}) {
    return {
      "path": path,
      "open_ms": steps?.openMs,
      "cache_ms": steps?.cacheMs,
      "self_sign_ms": steps?.selfSignMs,
      "finish_ms": finishMs,
      "screen_ms": screenMs,
      "outcome": error == null ? "ok" : "error",
      if (error != null) "failure": failure(error),
      if (error != null) "error_kind": TelemetryErrors.kind(error),
    };
  }

  static void unlock(
      {required String path,
      required int screenMs,
      UnlockSteps? steps,
      int? finishMs,
      Object? error}) {
    Telemetry.record(
        "secure_unlock",
        unlockFields(
            path: path,
            screenMs: screenMs,
            steps: steps,
            finishMs: finishMs,
            error: error));
  }

  /// Which kind of failure, from a fixed list (never the message).
  static String failure(Object error) => switch (error) {
        WrongRecoveryKeyException() => "wrong_key",
        MalformedRecoveryKeyException() => "malformed_key",
        NothingToUnlockException() => "nothing_to_unlock",
        _ => "other",
      };

  /// `history_keys_import` fields: [trigger] is unlock, approval or startup;
  /// [sessions] the number of keys the backup holds.
  static Map<String, Object?> importFields(
      {required String trigger,
      required int ms,
      int? sessions,
      Object? error}) {
    return {
      "trigger": trigger,
      "ms": ms,
      "sessions": sessions?.clamp(0, 1000000),
      "outcome": error == null ? "ok" : "error",
      if (error != null) "error_kind": TelemetryErrors.kind(error),
    };
  }

  static void historyImport(
      {required String trigger,
      required int ms,
      int? sessions,
      Object? error}) {
    Telemetry.record(
        "history_keys_import",
        importFields(
            trigger: trigger, ms: ms, sessions: sessions, error: error));
  }
}
