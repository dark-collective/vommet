// Vommet telemetry schema v19: sliding sync restarts (position resets and
// rooms sent again from scratch). Counts and one boolean only.

import 'dart:io';

import 'package:commet/telemetry/sync_stats.dart';
import 'package:commet/telemetry/telemetry_schema.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final schema = TelemetrySchema.parse(
      File("assets/telemetry/schema.json").readAsStringSync());

  test("schema is v19 or later", () {
    expect(schema.version, greaterThanOrEqualTo(19));
  });

  test("ss_first_round holds a boolean and counts", () {
    expect(
        schema.validateEvent({
          "e": "ss_first_round",
          "t": 2300,
          "had_position": true,
          "initial_rooms": 236,
          "rooms": 236,
          "resets": 1,
        }),
        isTrue);
    expect(
        schema.validateEvent({
          "e": "ss_first_round",
          "t": 2300,
          "had_position": "!room:example.org",
        }),
        isFalse);
    expect(schema.validateEvent({"e": "ss_first_round", "t": 1}), isFalse,
        reason: "had_position is required");
  });

  test("sync_stats takes the sliding sync restart counts", () {
    expect(
        schema.validateEvent({
          "e": "sync_stats",
          "t": 900000,
          "syncs": 120,
          "ss_resets": 2,
          "ss_initial_rooms": 472,
          "ss_initial_rounds": 3,
        }),
        isTrue);
  });

  test("a stored sliding sync token tells whether it has a position", () {
    expect(SyncStats.slidingSyncTokenHasPosition(null), isNull);
    expect(SyncStats.slidingSyncTokenHasPosition("s123_456"), isNull,
        reason: "a /sync v2 token");
    expect(
        SyncStats.slidingSyncTokenHasPosition(
            'ss1:{"pos":"42","td":"7","conn":"main"}'),
        isTrue);
    expect(SyncStats.slidingSyncTokenHasPosition('ss1:{"td":"7"}'), isFalse);
    expect(SyncStats.slidingSyncTokenHasPosition("ss1:not json"), isFalse);
  });
}
