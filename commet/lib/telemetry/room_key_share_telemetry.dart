// Vommet (schema v33): who each room key this device sent out reached, as
// the opt-in diagnostics event "room_key_share". One event per new outbound
// megolm session and per later send of the current one to devices learned
// of since. Counts only (members, missing/outdated device lists and the
// wait for them, devices blocked/withheld/reached/without an olm
// session/failed): never which room, users, devices or session ids. The
// event's time says how long after startup it happened.

import 'dart:async';

import 'package:commet/telemetry/telemetry.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart' as matrix;

class RoomKeyShareTelemetry {
  static final Expando<StreamSubscription<RoomKeyShareReport>> _subs =
      Expando();

  /// Starts reporting [client]'s room key shares. Safe to call more than
  /// once per client.
  static void track(matrix.Client client) {
    final keyManager = client.encryption?.keyManager;
    if (keyManager == null || _subs[client] != null) return;
    _subs[client] = keyManager.onRoomKeyShare.stream.listen(record);
  }

  static void record(RoomKeyShareReport report) {
    Telemetry.record("room_key_share", fields(report));
  }

  static String outcome(RoomKeyShareReport report) {
    if (report.devicesFailed > 0) return "failed";
    if (report.devicesReached > 0) return "sent";
    return "nobody";
  }

  static Map<String, Object?> fields(RoomKeyShareReport report) => {
        "kind": report.kind,
        "outcome": outcome(report),
        "users": report.users,
        "users_outdated": report.usersOutdated,
        "users_fetched": report.usersFetched,
        "users_without_devices": report.usersWithoutDevices,
        if (report.usersFetched > 0) ...{
          "fetch_ms": report.fetchMs,
          "fetch_timed_out": report.fetchTimedOut,
        },
        "devices": report.devices,
        "devices_blocked": report.devicesBlocked,
        "devices_withheld": report.devicesWithheld,
        "devices_reached": report.devicesReached,
        "devices_no_olm_session": report.devicesNoOlmSession,
        "devices_failed": report.devicesFailed,
        "ms": report.ms,
      };
}
