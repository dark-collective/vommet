// Vommet telemetry schema v20: freezes as they happen (`ui_stall`). A kind,
// durations and call context only.

import 'dart:io';

import 'package:commet/telemetry/telemetry_schema.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final schema = TelemetrySchema.parse(
      File("assets/telemetry/schema.json").readAsStringSync());

  test("schema is v20 or later", () {
    expect(schema.version, greaterThanOrEqualTo(20));
  });

  test("ui_stall carries only a kind, durations and call context", () {
    final stall = <String, Object>{
      "e": "ui_stall",
      "t": 187000,
      "kind": "platform",
      "ms": 5200,
      "ongoing": true,
      "foreground": true,
      "in_call": false,
      "since_call_end_s": 1,
      "call_participants": 14,
    };
    expect(schema.validateEvent(stall), isTrue);
    expect(
        schema.validateEvent(<String, Object>{
          "e": "ui_stall",
          "t": 1,
          "kind": "loop",
          "ms": 6000,
        }),
        isTrue);
    expect(
        schema
            .validateEvent(<String, Object>{"e": "ui_stall", "t": 1, "ms": 1}),
        isFalse,
        reason: "kind is required");
    for (final (key, value) in <(String, Object)>[
      ("kind", "gpu"),
      ("ms", -1),
      ("ongoing", "yes"),
      ("room", "!a:nether.im"),
      ("screen", "call view"),
    ]) {
      expect(schema.validateEvent({...stall, key: value}), isFalse,
          reason: key);
    }
  });
}
