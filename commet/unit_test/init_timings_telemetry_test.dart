// Vommet: the SDK's Client.init steps (Init_* timers) ride along in the
// app_ready `startup` timers, so a slow Matrix_client_init can be broken down
// on every platform. No schema change: `startup` already takes any code
// identifier with calls and total_ms, at most 64 entries.

import 'dart:io';

import 'package:commet/diagnostic/diagnostics.dart';
import 'package:commet/telemetry/init_timings_telemetry.dart';
import 'package:commet/telemetry/telemetry_schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;

matrix.InitTiming span(String name, int calls, int ms) =>
    matrix.InitTiming(name)
      ..calls = calls
      ..elapsed = Duration(milliseconds: ms);

void main() {
  final schema = TelemetrySchema.parse(
      File("assets/telemetry/schema.json").readAsStringSync());

  test("init steps follow the app's startup timers", () {
    final general = CumulativeDiagnostics("test")
      ..addResult("Matrix client init", const Duration(seconds: 48));
    final out = InitTimingsTelemetry.startupTimers(general: general, spans: [
      span("Init_db_device_keys_match", 5400, 41000),
      span("Init_db_rooms_parse", 1792, 900),
    ]);
    expect(out.map((t) => t["name"]), [
      "Matrix_client_init",
      "Init_db_device_keys_match",
      "Init_db_rooms_parse",
    ]);
    expect(out[1], {
      "name": "Init_db_device_keys_match",
      "calls": 5400,
      "total_ms": 41000,
    });
    final event = {
      "e": "app_ready",
      "t": 50000,
      "ms": 50000,
      "startup": out,
    };
    expect(schema.validateEvent(event), isTrue);
  });

  test("only Init_ identifiers are sent", () {
    final out = InitTimingsTelemetry.initTimers([
      span("Init_ok", 1, 1),
      span("Init_@user:example.org", 1, 1),
      span("Room !abc:example.org", 1, 1),
      span("Other_step", 1, 1),
    ]);
    expect(out.map((t) => t["name"]), ["Init_ok"]);
  });

  test("the list stays within the schema's 64 timers", () {
    final out = InitTimingsTelemetry.startupTimers(
      general: CumulativeDiagnostics("test"),
      spans: [
        for (var i = 0; i < 80; i++)
          span(
              "Init_step_${String.fromCharCode(97 + i ~/ 26)}"
              "${String.fromCharCode(97 + i % 26)}",
              1,
              1),
      ],
    );
    expect(out.length, InitTimingsTelemetry.maxTimers);
    expect(
        schema
            .validateEvent({"e": "app_ready", "t": 1, "ms": 1, "startup": out}),
        isTrue);
  });
}
