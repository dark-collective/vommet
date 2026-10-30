// Vommet telemetry schema v29: the frame counter's `repaint_stats` event.

import 'dart:convert';
import 'dart:io';

import 'package:commet/telemetry/repaint_stats.dart';
import 'package:commet/telemetry/telemetry_schema.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

FrameTiming frame(int buildMs, int rasterMs) {
  const us = 1000;
  return FrameTiming(
    vsyncStart: 0,
    buildStart: 0,
    buildFinish: buildMs * us,
    rasterStart: buildMs * us,
    rasterFinish: (buildMs + rasterMs) * us,
    rasterFinishWallTime: (buildMs + rasterMs) * us,
  );
}

void main() {
  final source = File("assets/telemetry/schema.json").readAsStringSync();
  final schema = TelemetrySchema.parse(source);

  setUp(RepaintStats.resetForTest);
  tearDown(RepaintStats.resetForTest);

  test("schema is v29 and still accepts v28", () {
    expect(schema.version, greaterThanOrEqualTo(29));
    expect((jsonDecode(source) as Map)["accepts"], contains(28));
  });

  test("repaint_stats validates; room ids and other views don't", () {
    final ok = {
      "e": "repaint_stats",
      "t": 900000,
      "view": "room",
      "minutes": 15,
      "frames": 120,
      "frames_max_min": 40,
      "build_p95_ms": 4,
      "raster_p95_ms": 8,
      "native_draws": 3600,
      "native_draws_max_min": 300,
      "native_paints": 3600,
    };
    expect(schema.validateEvent(ok), isTrue);
    expect(schema.validateEvent({...ok, "view": "!abc:example.org"}), isFalse);
    expect(
        schema.validateEvent({...ok, "room_id": "!abc:example.org"}), isFalse);
    final noNative = Map.of(ok)
      ..remove("native_draws")
      ..remove("native_draws_max_min")
      ..remove("native_paints");
    expect(schema.validateEvent(noNative), isTrue);
  });

  test("minutes are filed under the view showing when they end", () async {
    RepaintStats.collectForTest();

    RepaintStats.mainView = RepaintView.home;
    RepaintStats.addTimingsForTest([frame(2, 3), frame(2, 3)]);
    await RepaintStats.closeMinuteForTest();
    await RepaintStats.closeMinuteForTest(); // an idle minute

    RepaintStats.mainView = RepaintView.room;
    RepaintStats.addTimingsForTest(List.generate(30, (_) => frame(10, 30)));
    await RepaintStats.closeMinuteForTest();

    RepaintStats.settingsOpened();
    RepaintStats.addTimingsForTest([frame(1, 1)]);
    await RepaintStats.closeMinuteForTest();
    RepaintStats.settingsClosed();
    expect(RepaintStats.view, RepaintView.room);

    final events = {
      for (final f in RepaintStats.eventFields()) f["view"]: f,
    };
    expect(events.keys, unorderedEquals(["home", "room", "settings"]));
    expect(events["home"]!["minutes"], 2);
    expect(events["home"]!["frames"], 2);
    expect(events["home"]!["frames_max_min"], 2);
    expect(events["room"]!["frames"], 30);
    expect(events["room"]!["build_p95_ms"], 12);
    expect(events["room"]!["raster_p95_ms"], 33);
    // No native counter in tests (it's Linux-only and native).
    expect(events["room"]!["native_draws"], isNull);
    for (final f in events.values) {
      final ev = <String, Object>{"e": "repaint_stats", "t": 1};
      f.forEach((k, v) {
        if (v != null) ev[k] = v;
      });
      expect(schema.validateEvent(ev), isTrue, reason: "$f");
    }
  });

  test("nothing is kept for telemetry when only the developer page counts",
      () async {
    RepaintStats.addTimingsForTest([frame(2, 3)]);
    await RepaintStats.closeMinuteForTest();
    expect(RepaintStats.eventFields(), isEmpty);
  });
}
