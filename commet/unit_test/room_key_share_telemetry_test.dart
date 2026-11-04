// Vommet telemetry schema v33: room_key_share reports who a room key we
// sent out reached, in counts only.

import 'dart:io';

import 'package:commet/telemetry/room_key_share_telemetry.dart';
import 'package:commet/telemetry/telemetry_schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/encryption.dart';

void main() {
  final schema = TelemetrySchema.parse(
    File("assets/telemetry/schema.json").readAsStringSync(),
  );

  Map<String, Object?> event(RoomKeyShareReport r) => {
        "e": "room_key_share",
        "t": 20704,
        ...RoomKeyShareTelemetry.fields(r),
      };

  RoomKeyShareReport report(
    String kind, {
    int reached = 0,
    int failed = 0,
    int fetched = 0,
  }) =>
      RoomKeyShareReport(kind: kind)
        ..users = 12
        ..usersOutdated = 9
        ..usersFetched = fetched
        ..usersWithoutDevices = 1
        ..fetchMs = 1800
        ..fetchTimedOut = true
        ..devices = 40
        ..devicesBlocked = 1
        ..devicesWithheld = 2
        ..devicesReached = reached
        ..devicesNoOlmSession = 3
        ..devicesFailed = failed
        ..ms = 2400;

  test("schema is v33", () {
    expect(schema.version, greaterThanOrEqualTo(33));
  });

  test("every report the SDK can make validates", () {
    for (final kind in ["new_session", "added_devices"]) {
      for (final r in [
        report(kind, reached: 34, fetched: 9),
        report(kind),
        report(kind, reached: 20, failed: 14),
      ]) {
        expect(schema.validateEvent(event(r)), isTrue, reason: kind);
      }
    }
  });

  test("outcome words", () {
    expect(
      RoomKeyShareTelemetry.outcome(report("new_session", reached: 3)),
      "sent",
    );
    expect(RoomKeyShareTelemetry.outcome(report("new_session")), "nobody");
    expect(
      RoomKeyShareTelemetry.outcome(
        report("new_session", reached: 3, failed: 1),
      ),
      "failed",
    );
  });

  test("the fetch time is only sent when lists were fetched", () {
    expect(
      RoomKeyShareTelemetry.fields(report("new_session")),
      isNot(contains("fetch_ms")),
    );
    final fetched = RoomKeyShareTelemetry.fields(
      report("new_session", reached: 1, fetched: 9),
    );
    expect(fetched["fetch_ms"], 1800);
    expect(fetched["fetch_timed_out"], true);
  });

  test("only counts, fixed words and booleans", () {
    final fields = RoomKeyShareTelemetry.fields(
      report("added_devices", reached: 5, fetched: 2),
    );
    for (final MapEntry(:key, :value) in fields.entries) {
      expect(
        value is int || value is bool || key == "kind" || key == "outcome",
        isTrue,
        reason: key,
      );
    }
    expect(
      schema.validateEvent({
        ...event(report("new_session")),
        "room_id": "!a:b",
      }),
      isFalse,
    );
  });
}
