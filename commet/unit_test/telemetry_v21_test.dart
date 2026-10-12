// Vommet telemetry schema v21: the first sync's timeline and how long the
// UI isolate was blocked until then. Times and counts only.

import 'dart:io';

import 'package:commet/telemetry/telemetry.dart';
import 'package:commet/telemetry/telemetry_schema.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final schema = TelemetrySchema.parse(
      File("assets/telemetry/schema.json").readAsStringSync());

  test("schema is v21", () {
    expect(schema.version, 21);
  });

  test("first_sync holds times and counts", () {
    expect(
        schema.validateEvent({
          "e": "first_sync",
          "t": 9600,
          "request_at_ms": 900,
          "response_at_ms": 8400,
          "done_at_ms": 9600,
          "blocked_ms": 6200,
          "blocked_worst_ms": 1800,
          "stalls_100ms": 14,
        }),
        isTrue);
    expect(schema.validateEvent({"e": "first_sync", "t": 1}), isFalse,
        reason: "done_at_ms is required");
  });

  test("the startup room work timers ship", () {
    for (final name in [
      "Deferred room state query",
      "Deferred room state apply",
      "Room list update",
      "Space rooms list update",
      "Deferred room state callbacks",
    ]) {
      expect(Telemetry.knownGeneralTimers, contains(Telemetry.timerName(name)),
          reason: name);
    }
  });
}
