// Vommet (schema v24): what happened to shared encrypted history (MSC4268),
// as the opt-in diagnostics event "history_share". One event per history
// bundle we sent (we invited someone) or received (we accepted an invite),
// and per new outbound megolm session (whether people invited later may
// get it). Fixed outcome words and counts only: never which room, who was
// invited, keys or session ids.

import 'dart:async';

import 'package:commet/telemetry/telemetry.dart';
import 'package:matrix/encryption/history_sharing.dart';
import 'package:matrix/matrix.dart' as matrix;

class HistorySharingTelemetry {
  static final Expando<StreamSubscription<HistorySharingReport>> _subs =
      Expando();

  /// Starts reporting [client]'s history sharing outcomes. Safe to call
  /// more than once per client.
  static void track(matrix.Client client) {
    final sharing = client.encryption?.historySharing;
    if (sharing == null || _subs[client] != null) return;
    _subs[client] = sharing.onReport.stream.listen(record);
  }

  static void record(HistorySharingReport report) {
    Telemetry.record("history_share", fields(report));
  }

  static Map<String, Object?> fields(HistorySharingReport report) => {
        "direction": report.direction,
        "outcome": report.outcome,
        if (report.direction != "outbound_session") ...{
          "keys": report.keys,
          "withheld": report.withheld,
          "ms": report.ms,
        },
        if (report.direction == "receive") "skipped": report.skipped,
        if (report.direction == "send") "devices": report.devices,
      };
}
