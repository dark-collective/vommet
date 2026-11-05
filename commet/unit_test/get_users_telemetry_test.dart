// Vommet: the loads of rooms' stored members (SDK getUsers(room), timed by
// GetUsersStats) ride along in the perf_summary `db` timers: Get_users_room
// (loads, total time) and Get_users_room_max (slowest load: its time, and its
// member count as `calls`), since the previous summary. No schema change:
// `db` already takes any code identifier with calls and total_ms, at most 64.

import 'dart:io';

import 'package:commet/telemetry/get_users_telemetry.dart';
import 'package:commet/telemetry/telemetry_schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;

void main() {
  final schema = TelemetrySchema.parse(
      File("assets/telemetry/schema.json").readAsStringSync());

  Map<String, dynamic> summary(List<Map<String, Object>> db) => {
        "e": "perf_summary",
        "t": 900000,
        "uptime_s": 900,
        "timers": const <Map<String, Object>>[],
        "db": db,
      };

  test("count, total and the slowest load, valid for the schema", () {
    final out = GetUsersTelemetry.timers(const matrix.GetUsersSnapshot(
        1800, Duration(milliseconds: 46000), Duration(milliseconds: 310), 250));
    expect(out, [
      {"name": "Get_users_room", "calls": 1800, "total_ms": 46000},
      {"name": "Get_users_room_max", "calls": 250, "total_ms": 310},
    ]);
    expect(schema.validateEvent(summary(out)), isTrue);
  });

  test("nothing when no load ran", () {
    expect(
        GetUsersTelemetry.timers(
            const matrix.GetUsersSnapshot(0, Duration.zero, Duration.zero, 0)),
        isEmpty);
  });

  test("taken from GetUsersStats once per summary, after the db timers", () {
    matrix.GetUsersStats.take();
    matrix.GetUsersStats.add(const Duration(milliseconds: 12), 2);
    matrix.GetUsersStats.add(const Duration(milliseconds: 90), 400);
    final db = [
      {"name": "Get_users", "calls": 3, "total_ms": 20},
    ];
    final out = GetUsersTelemetry.appendTo(db);
    expect(out.map((t) => t["name"]),
        ["Get_users", "Get_users_room", "Get_users_room_max"]);
    expect(out[1], {"name": "Get_users_room", "calls": 2, "total_ms": 102});
    expect(
        out[2], {"name": "Get_users_room_max", "calls": 400, "total_ms": 90});
    expect(schema.validateEvent(summary(out)), isTrue);
    // The next summary starts over.
    expect(GetUsersTelemetry.appendTo(const []), isEmpty);
  });

  test("the list stays within the schema's 64 timers", () {
    matrix.GetUsersStats.add(const Duration(milliseconds: 1), 1);
    final db = [
      for (var i = 0; i < 63; i++)
        <String, Object>{"name": "T$i", "calls": 1, "total_ms": 1},
    ];
    final out = GetUsersTelemetry.appendTo(db);
    expect(out.length, 64);
    expect(out.last["name"], "Get_users_room");
    expect(schema.validateEvent(summary(out)), isTrue);
    matrix.GetUsersStats.take();
  });
}
