// Vommet (schema v22): how reply previews find the message they quote, as
// counters for the opt-in "reply_lookup" diagnostics event. A reply whose
// quoted message isn't in the loaded timeline asks the local store, then the
// homeserver; when neither has it the preview stays "Loading". These counts
// tell "the user's homeserver doesn't have that event" (common in federated
// rooms) apart from a client bug. Plain ints in memory, reported with the
// 15-minute perf summary and when the app goes to the background; never an
// event, room, user or server name.

import 'dart:math' as math;

import 'package:commet/telemetry/telemetry.dart';
import 'package:commet/telemetry/telemetry_errors.dart';

class ReplyLookupStats {
  static int _lookups = 0;
  static int _foundCached = 0;
  static int _foundServer = 0;
  static int _missing = 0;
  static int _errNotFound = 0;
  static int _errForbidden = 0;
  static int _errTimeout = 0;
  static int _errOther = 0;
  static int _federatedLookups = 0;
  static int _federatedMissing = 0;
  static int _worstMs = 0;

  /// Whether the room lives on another server than the account: the room
  /// ID's server part against the user ID's. Null when either has none
  /// (e.g. room versions whose IDs carry no server name). Neither name is
  /// kept; only the yes/no leaves this function.
  static bool? federatedRoom(String roomId, String? userId) {
    if (userId == null) return null;
    final r = roomId.indexOf(":");
    final u = userId.indexOf(":");
    if (r < 0 || u < 0) return null;
    return roomId.substring(r + 1) != userId.substring(u + 1);
  }

  /// Count one finished lookup: found in the local store ([fromServer]
  /// false), fetched from the homeserver, or not found anywhere ([found]
  /// false).
  static void add(
      {required bool found,
      required bool fromServer,
      required int ms,
      bool? federated}) {
    if (!Telemetry.enabled) return;
    _lookups++;
    if (!found) {
      _missing++;
    } else if (fromServer) {
      _foundServer++;
    } else {
      _foundCached++;
    }
    _note(ms, federated, missing: !found);
  }

  /// Count one lookup that failed with [error].
  static void addError(Object error, {required int ms, bool? federated}) {
    if (!Telemetry.enabled) return;
    _lookups++;
    switch (errorBucket(error)) {
      case "not_found":
        _errNotFound++;
      case "forbidden":
        _errForbidden++;
      case "timeout":
        _errTimeout++;
      default:
        _errOther++;
    }
    _note(ms, federated, missing: false);
  }

  static void _note(int ms, bool? federated, {required bool missing}) {
    if (federated == true) {
      _federatedLookups++;
      if (missing) _federatedMissing++;
    }
    _worstMs = math.max(_worstMs, ms);
  }

  /// not_found / forbidden / timeout / other, from the shared error helpers.
  static String errorBucket(Object error) {
    final kind = TelemetryErrors.kind(error);
    final code = TelemetryErrors.errcode(error);
    if (kind == "http_404" || kind == "not_found" || code == "M_NOT_FOUND") {
      return "not_found";
    }
    if (kind == "http_403" || code == "M_FORBIDDEN") return "forbidden";
    if (kind == "timeout") return "timeout";
    return "other";
  }

  /// Record the counters as one "reply_lookup" event and start again.
  /// Nothing is recorded when there were no lookups.
  static void report() {
    if (_lookups == 0) return;
    int c(int v) => v.clamp(0, 1000000);
    Telemetry.record("reply_lookup", {
      "lookups": c(_lookups),
      "found_cached": c(_foundCached),
      "found_server": c(_foundServer),
      "missing": c(_missing),
      "errors_not_found": c(_errNotFound),
      "errors_forbidden": c(_errForbidden),
      "errors_timeout": c(_errTimeout),
      "errors_other": c(_errOther),
      "federated_lookups": c(_federatedLookups),
      "federated_missing": c(_federatedMissing),
      "worst_ms": _worstMs.clamp(0, 86400000),
    });
    reset();
  }

  static void reset() {
    _lookups = _foundCached = _foundServer = _missing = 0;
    _errNotFound = _errForbidden = _errTimeout = _errOther = 0;
    _federatedLookups = _federatedMissing = _worstMs = 0;
  }
}
