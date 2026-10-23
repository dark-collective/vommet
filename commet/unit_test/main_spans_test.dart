// Vommet: MainSpans names what holds the UI isolate's event loop. Zone spans
// time every callback scheduled inside them, sync spans one section; a span's
// own time leaves out spans inside it; a LoopLag tick a second or more late is
// broken down by the spans' own time since the previous tick (Stall_*), which
// also covers a block made of a microtask chain. Reported as `timers` entries,
// so no schema change.

import 'dart:async';
import 'dart:io';

import 'package:commet/telemetry/main_spans.dart';
import 'package:commet/telemetry/telemetry_schema.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final schema = TelemetrySchema.parse(
      File("assets/telemetry/schema.json").readAsStringSync());

  // A fake clock: [burn] moves it on, as if the code ran that long.
  var nowUs = 0;
  void burn(int ms) => nowUs += ms * 1000;

  setUp(() {
    MainSpans.reset();
    MainSpans.enabled = true;
    nowUs = 0;
    MainSpans.debugClock = () => nowUs;
  });
  tearDown(() {
    MainSpans.debugClock = null;
    MainSpans.enabled = false;
  });

  // An await on a span's future resumes inside that span's callback; let it
  // end before reading the figures.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  Map<String, Object> find(List<Map<String, Object>> out, String name) =>
      out.firstWhere((t) => t["name"] == name,
          orElse: () => throw StateError("no $name in $out"));

  test("a zone times the callbacks scheduled inside it", () async {
    await MainSpans.zone("Sub", () async {
      burn(5);
      await Future<void>.delayed(Duration.zero);
      burn(7);
      scheduleMicrotask(() => burn(3));
      await Future<void>.value();
    });
    await settle();
    final s = MainSpans.stats.firstWhere((s) => s.name == "Sub");
    expect(s.ownUs, 15000);
    expect(s.calls, greaterThanOrEqualTo(3));
    expect(s.worstUs, 7000);
  });

  test("own time leaves out inner sync spans and inner zones", () async {
    await MainSpans.zone("Outer", () async {
      burn(10);
      MainSpans.time("Inner", () => burn(200));
      await MainSpans.zone("Child", () async {
        burn(4);
        await Future<void>.delayed(Duration.zero);
        burn(6);
      });
    });
    await settle();
    final by = {for (final s in MainSpans.stats) s.name: s};
    expect(by["Outer"]!.ownUs, 10000);
    expect(by["Inner"]!.ownUs, 200000);
    expect(by["Inner"]!.slowCalls, 1);
    expect(by["Child"]!.ownUs, 10000);
  });

  test("code resumed inside another span's callback counts for its own span",
      () async {
    await MainSpans.zone("App", () async {
      await MainSpans.zone("Lib", () async {
        await Future<void>.delayed(Duration.zero);
        burn(5);
      });
      // Runs nested in Lib's last callback (the future completes there).
      burn(40);
    });
    await settle();
    final by = {for (final s in MainSpans.stats) s.name: s};
    expect(by["Lib"]!.ownUs, 5000);
    expect(by["App"]!.ownUs, 40000);
  });

  test("zones forked inside a span still count for it", () async {
    await MainSpans.zone("Host", () async {
      await runZoned(() async {
        await Future<void>.delayed(Duration.zero);
        burn(30);
      });
    });
    await settle();
    final s = MainSpans.stats.firstWhere((s) => s.name == "Host");
    expect(s.ownUs, 30000);
  });

  test("a blocked tick is split by the spans that ran since the last one",
      () async {
    MainSpans.tick(0); // the first tick sets the baseline
    await MainSpans.zone("Rooms", () async {
      // A microtask chain: no single callback is long.
      for (var i = 0; i < 100; i++) {
        burn(80);
        await Future<void>.value();
      }
    });
    MainSpans.time("Notify", () => burn(2500));
    MainSpans.tick(10500);
    final out = MainSpans.sinceLaunch();
    expect(find(out, "Stall_Rooms"), {
      "name": "Stall_Rooms",
      "calls": 1,
      "total_ms": 8000,
    });
    expect(find(out, "Stall_Notify")["total_ms"], 2500);
    // Spans cover the whole 10.5 s, so nothing is left for "none".
    expect(out.where((t) => t["name"] == "Stall_none"), isEmpty);
  });

  test("the uncovered rest of a blocked tick is Stall_none", () {
    MainSpans.tick(0);
    MainSpans.time("Small", () => burn(300));
    MainSpans.tick(11000);
    final out = MainSpans.sinceLaunch();
    expect(find(out, "Stall_Small")["total_ms"], 300);
    expect(find(out, "Stall_none"), {
      "name": "Stall_none",
      "calls": 1,
      "total_ms": 10700,
    });
  });

  test("ticks that are not late, and the first tick, are no stall", () {
    MainSpans.time("Busy", () => burn(3000));
    MainSpans.tick(3000); // first tick: no baseline yet
    MainSpans.time("Busy", () => burn(400));
    MainSpans.tick(400);
    final out = MainSpans.sinceLaunch();
    expect(
        out.where((t) => (t["name"] as String).startsWith("Stall_")), isEmpty);
    expect(find(out, "Main_Busy"), {
      "name": "Main_Busy",
      "calls": 2,
      "total_ms": 3400,
    });
    expect(find(out, "Main_Busy_max"), {
      "name": "Main_Busy_max",
      "calls": 2,
      "total_ms": 3000,
    });
  });

  test("a pause restarts the tick window", () {
    MainSpans.tick(0);
    MainSpans.time("Bg", () => burn(5000));
    MainSpans.pause();
    MainSpans.tick(20000);
    expect(
        MainSpans.sinceLaunch()
            .where((t) => (t["name"] as String).startsWith("Stall_")),
        isEmpty);
  });

  test("phase time is the zone body's wall time", () async {
    final gate = Completer<void>();
    final f = MainSpans.zone(phase: true, "Setup", () async {
      burn(2);
      await gate.future;
    });
    burn(5000); // waiting, outside the span
    gate.complete();
    await f;
    final out = MainSpans.sinceLaunch();
    expect(find(out, "Phase_Setup")["total_ms"], 5002);
    expect(find(out, "Main_Setup")["total_ms"], 2);
  });

  test("intervals report what changed since the previous one", () {
    MainSpans.tick(0);
    MainSpans.time("Work", () => burn(1500));
    MainSpans.tick(1500);
    final first = MainSpans.takeInterval();
    expect(find(first, "Main_Work")["total_ms"], 1500);
    expect(find(first, "Stall_Work")["total_ms"], 1500);
    MainSpans.time("Work", () => burn(20));
    final second = MainSpans.takeInterval();
    expect(find(second, "Main_Work"),
        {"name": "Main_Work", "calls": 1, "total_ms": 20});
    expect(second.where((t) => t["name"] == "Main_Work_max"), isEmpty);
    expect(second.where((t) => (t["name"] as String).startsWith("Stall_")),
        isEmpty);
    expect(MainSpans.takeInterval(), isEmpty);
  });

  test("the list is capped and valid for app_ready and perf_summary", () {
    MainSpans.tick(0);
    for (var i = 0; i < 40; i++) {
      MainSpans.time("Span_$i", () => burn(200 + i));
    }
    MainSpans.tick(9000);
    final out = MainSpans.sinceLaunch(max: 30);
    expect(out, hasLength(30));
    // Stall shares first, biggest first.
    expect(out.first["name"], "Stall_Span_39");
    expect(MainSpans.sinceLaunch(max: 0), isEmpty);
    expect(
        schema.validateEvent({
          "e": "app_ready",
          "t": 14000,
          "ms": 14000,
          "startup": MainSpans.sinceLaunch(),
        }),
        isTrue);
    expect(
        schema.validateEvent({
          "e": "perf_summary",
          "t": 900000,
          "uptime_s": 900,
          "timers": MainSpans.takeInterval(),
        }),
        isTrue);
  });

  test("off (no consent), nothing is counted", () async {
    MainSpans.enabled = false;
    MainSpans.time("Off", () => burn(500));
    await MainSpans.zone("OffZone", () async {
      await Future<void>.delayed(Duration.zero);
      burn(500);
    }, phase: true);
    await settle();
    MainSpans.tick(0);
    MainSpans.tick(5000);
    expect(MainSpans.sinceLaunch().where((t) => t["name"] != "Stall_none"),
        isEmpty);
  });

  test("the first tick after LoopLag (re)starts can be a stall", () {
    MainSpans.resume();
    MainSpans.time("Early", () => burn(11000));
    MainSpans.tick(11000);
    expect(find(MainSpans.sinceLaunch(), "Stall_Early")["total_ms"], 11000);
  });

  test("shares are scaled to the blocked time", () {
    MainSpans.resume();
    // 400 ms of normal work in the tick period, then a 2 s block.
    MainSpans.time("Normal", () => burn(400));
    MainSpans.time("Block", () => burn(2000));
    MainSpans.tick(2000);
    final out = MainSpans.sinceLaunch();
    final block = find(out, "Stall_Block")["total_ms"] as int;
    final normal = find(out, "Stall_Normal")["total_ms"] as int;
    expect(block + normal, lessThanOrEqualTo(2000));
    expect(block, greaterThan(1600));
    expect(out.where((t) => t["name"] == "Stall_none"), isEmpty);
  });

  test("without phase an unawaited failure still reaches the zone handler",
      () async {
    final errors = <Object>[];
    final done = Completer<void>();
    runZonedGuarded(() {
      MainSpans.zone<void>("Fails", () async {
        await Future<void>.delayed(Duration.zero);
        throw StateError("boom");
      });
    }, (e, _) {
      errors.add(e);
      done.complete();
    });
    await done.future.timeout(const Duration(seconds: 5));
    expect(errors.single, isStateError);
  });

  test("a span nested in itself counts once", () {
    MainSpans.time("Same", () {
      burn(5);
      MainSpans.time("Same", () => burn(5));
    });
    final s = MainSpans.stats.firstWhere((s) => s.name == "Same");
    expect(s.calls, 1);
    expect(s.ownUs, 10000);
  });

  test("an exception still closes the span", () {
    expect(
        () => MainSpans.time("Throws", () {
              burn(9);
              throw StateError("x");
            }),
        throwsStateError);
    MainSpans.time("After", () => burn(1));
    final by = {for (final s in MainSpans.stats) s.name: s};
    expect(by["Throws"]!.ownUs, 9000);
    expect(by["After"]!.ownUs, 1000);
  });
}
