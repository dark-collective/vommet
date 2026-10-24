// Vommet telemetry schema v31: the `ssss_repair` event (Vommet issue 526,
// removing secret copies an old recovery key still opens).

import 'dart:convert';
import 'dart:io';

import 'package:commet/telemetry/telemetry_schema.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File("assets/telemetry/schema.json").readAsStringSync();
  final schema = TelemetrySchema.parse(source);

  test("schema is v31 and still accepts v30", () {
    expect(schema.version, greaterThanOrEqualTo(31));
    expect((jsonDecode(source) as Map)["accepts"], contains(30));
  });

  test("ssss_repair validates with counts and an outcome only", () {
    final cleanup = {
      "e": "ssss_repair",
      "t": 120000,
      "trigger": "unlock",
      "outcome": "repaired",
      "pending": 4,
      "stripped": 4,
      "removed": 4,
      "kept": 0,
      "failed": 0,
      "retired_keys": 1,
      "again": false,
    };
    expect(schema.validateEvent(cleanup), isTrue);
    for (final outcome in [
      "clean",
      "partial",
      "kept",
      "not_default_key",
      "raced",
      "failed",
    ]) {
      expect(schema.validateEvent({...cleanup, "outcome": outcome}), isTrue,
          reason: outcome);
    }
    expect(schema.validateEvent({...cleanup, "trigger": "check"}), isTrue);

    final startup = {
      "e": "ssss_repair",
      "t": 30000,
      "trigger": "startup",
      "outcome": "pending",
      "pending": 3,
      "retired_keys": 2,
      "again": true,
    };
    expect(schema.validateEvent(startup), isTrue);
  });

  test("ssss_repair has nowhere to put a key id or a secret", () {
    final ok = {
      "e": "ssss_repair",
      "t": 1,
      "trigger": "check",
      "outcome": "kept",
      "kept": 1,
    };
    expect(schema.validateEvent(ok), isTrue);
    expect(schema.validateEvent({...ok, "key_id": "abcDEF123"}), isFalse);
    expect(
        schema.validateEvent({...ok, "secret_type": "m.cross_signing.master"}),
        isFalse);
    expect(schema.validateEvent({...ok, "outcome": "abcDEF123"}), isFalse);
    expect(schema.validateEvent({...ok, "trigger": "settings"}), isFalse);
    expect(schema.validateEvent({...ok, "kept": -1}), isFalse);
    final noOutcome = Map.of(ok)..remove("outcome");
    expect(schema.validateEvent(noOutcome), isFalse);
  });
}
