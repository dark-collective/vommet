// Vommet issue 526: before SDK ss.20, "replace my recovery key" left every
// secret (cross-signing keys, backup key) readable with the OLD recovery key
// too. Accounts that replaced their key then still hold those old copies on
// the server. They can only be removed safely with the CURRENT key in hand
// (the SDK proves the current copy is the live secret first), and the app
// never keeps that key: so the cleanup runs whenever the user enters it
// anyway (unlocking secure messaging, checking their key). See
// SSSS.stripRetiredKeyCopies in the SDK for the safety rules.

import 'dart:async';
import 'dart:convert';

import 'package:commet/config/preferences/string_list_preference.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/telemetry/telemetry.dart';
import 'package:crypto/crypto.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart' as matrix;

class SsssRepair {
  /// Accounts (as a salted hash, never the user ID) whose cleanup finished.
  static final StringListPreference _done =
      StringListPreference("ssss_retired_copies_cleaned", defaultValue: []);

  /// Bounded so a slow server never holds up the unlock it rides on.
  static const timeout = Duration(seconds: 30);

  static String _tag(String userId) =>
      sha256.convert(utf8.encode("vommet-ssss-repair:$userId")).toString();

  static bool _isDone(matrix.Client mx) =>
      mx.userID != null && _done.value.contains(_tag(mx.userID!));

  /// The cleanup finished for this account on this install.
  static bool isDone(matrix.Client mx) => _isDone(mx);

  /// Old-key copies wait for the user's current key, and the cleanup isn't
  /// done yet: the "Still have your recovery key?" check-in is brought
  /// forward for these (SecureSetupRecords.updateRepairCheckIn).
  static bool waiting(matrix.Client mx) => pending(mx) > 0 && !_isDone(mx);

  /// The user typed an OLDER recovery key where the current one was asked
  /// for (the check-in while copies wait): counts only, like [run].
  static void recordOldKeyEntered(matrix.Client mx) {
    Telemetry.record(
        "ssss_repair",
        fields(const SsssRepairResult(SsssRepairOutcome.notDefaultKey), "check",
            pending: pending(mx), again: _isDone(mx)));
  }

  /// Secrets this device could clean up once the user enters their current
  /// recovery key. Local account data only, no network.
  static int pending(matrix.Client mx) {
    final ssss = mx.encryption?.ssss;
    if (ssss == null) return 0;
    return ssss
        .retiredKeyCopies()
        .keys
        .where(SSSS.retiredCopyRepairTypes.contains)
        .length;
  }

  /// Remove old-key copies with [handle], when it is the unlocked default
  /// key. Never throws and never waits longer than [timeout]; does nothing
  /// (no request) when there is nothing to clean up. [trigger] says which
  /// user action brought the key ("unlock" or "check").
  static Future<SsssRepairResult?> run(
    matrix.Client mx,
    OpenSSSS handle, {
    required String trigger,
  }) async {
    try {
      final ssss = mx.encryption?.ssss;
      if (ssss == null ||
          !handle.isUnlocked ||
          handle.keyId != ssss.defaultKeyId) {
        return null;
      }
      final before = pending(mx);
      if (before == 0) {
        await _markDone(mx);
        return null;
      }
      final again = _isDone(mx);
      final result = await handle.stripRetiredKeyCopies().timeout(timeout);
      Log.i("Old recovery key cleanup ($trigger): $result");
      if (result.outcome == SsssRepairOutcome.repaired ||
          result.outcome == SsssRepairOutcome.clean) {
        await _markDone(mx);
      }
      Telemetry.record("ssss_repair",
          fields(result, trigger, pending: before, again: again));
      return result;
    } catch (e, s) {
      // The unlock it rides on must go on regardless.
      Log.onError(e, s, content: "Old recovery key cleanup failed");
      Telemetry.record(
          "ssss_repair",
          fields(const SsssRepairResult(SsssRepairOutcome.failed), trigger,
              again: false));
      return null;
    }
  }

  /// Once per account per session (with crypto_state): how many secrets
  /// still wait for the user's key. Nothing when there are none.
  static void recordPending(matrix.Client mx) {
    final n = pending(mx);
    if (n == 0) return;
    final retired = mx.encryption!.ssss
        .retiredKeyCopies()
        .values
        .expand((ids) => ids)
        .toSet()
        .length;
    Telemetry.record("ssss_repair", {
      "trigger": "startup",
      "outcome": "pending",
      "pending": n,
      "retired_keys": retired,
      "again": _isDone(mx),
    });
  }

  /// The `ssss_repair` telemetry event: counts and outcome only, never key
  /// ids or secrets.
  static Map<String, Object?> fields(SsssRepairResult r, String trigger,
          {int? pending, required bool again}) =>
      {
        "trigger": trigger,
        "outcome": outcomeName(r.outcome),
        "pending": pending,
        "stripped": r.stripped,
        "removed": r.removed,
        "kept": r.kept,
        "failed": r.failed,
        "retired_keys": r.retiredKeys,
        "again": again,
      };

  static String outcomeName(SsssRepairOutcome o) => switch (o) {
        SsssRepairOutcome.clean => "clean",
        SsssRepairOutcome.repaired => "repaired",
        SsssRepairOutcome.partial => "partial",
        SsssRepairOutcome.kept => "kept",
        SsssRepairOutcome.notDefaultKey => "not_default_key",
        SsssRepairOutcome.raced => "raced",
        SsssRepairOutcome.failed => "failed",
      };

  static Future<void> _markDone(matrix.Client mx) async {
    final id = mx.userID;
    if (id == null || _isDone(mx)) return;
    await _done.set([..._done.value, _tag(id)]);
  }
}
