import 'dart:async';

import 'package:commet/utils/profile_field_cache.dart';
import 'package:test/test.dart';

void main() {
  late DateTime now;
  late Map<String, int> calls;
  late Map<String, Map<String, dynamic>> server;
  late Set<String> failing;

  Future<Map<String, dynamic>> fetch(String userId) async {
    calls[userId] = (calls[userId] ?? 0) + 1;
    await Future<void>.delayed(Duration.zero);
    if (failing.contains(userId)) throw Exception("unreachable");
    return Map.of(server[userId]!);
  }

  ProfileFieldCache makeCache({int maxEntries = 2000, int maxConcurrent = 4}) =>
      ProfileFieldCache(fetch,
          now: () => now, maxEntries: maxEntries, maxConcurrent: maxConcurrent);

  setUp(() {
    now = DateTime(2026, 10, 8, 12);
    calls = {};
    failing = {};
    server = {
      "@a:x": {"displayname": "A"},
      "@b:x": {"displayname": "B"},
      "@c:x": {"displayname": "C"},
    };
  });

  test("fresh entry is served from memory", () async {
    final cache = makeCache();
    expect((await cache.get("@a:x"))!["displayname"], "A");
    expect((await cache.get("@a:x"))!["displayname"], "A");
    expect(calls["@a:x"], 1);
  });

  test("concurrent lookups share one request", () async {
    final cache = makeCache();
    await Future.wait(
        [cache.get("@a:x"), cache.get("@a:x"), cache.get("@a:x")]);
    expect(calls["@a:x"], 1);
  });

  test("stale entry answers at once and refreshes in the background", () async {
    final cache = makeCache();
    final updates = <String>[];
    cache.onUpdated.listen(updates.add);
    await cache.get("@a:x");

    server["@a:x"] = {"displayname": "A2"};
    now = now.add(const Duration(minutes: 11));

    expect((await cache.get("@a:x"))!["displayname"], "A");
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(calls["@a:x"], 2);
    expect(cache.peek("@a:x")!["displayname"], "A2");
    expect(updates, ["@a:x"]);
  });

  test("forceRefresh waits for the server", () async {
    final cache = makeCache();
    await cache.get("@a:x");
    server["@a:x"] = {"displayname": "A2"};
    expect((await cache.get("@a:x", forceRefresh: true))!["displayname"], "A2");
  });

  test("invalidate forgets the user", () async {
    final cache = makeCache();
    await cache.get("@a:x");
    cache.invalidate("@a:x");
    expect(cache.peek("@a:x"), isNull);
    await cache.get("@a:x");
    expect(calls["@a:x"], 2);
  });

  test("failure with nothing cached throws, then backs off", () async {
    final cache = makeCache();
    failing.add("@a:x");
    await expectLater(cache.get("@a:x"), throwsException);
    expect(await cache.get("@a:x"), isNull);
    expect(calls["@a:x"], 1);

    now = now.add(const Duration(minutes: 3));
    failing.clear();
    expect((await cache.get("@a:x"))!["displayname"], "A");
    expect(calls["@a:x"], 2);
  });

  test("failure keeps serving the old fields", () async {
    final cache = makeCache();
    await cache.get("@a:x");
    failing.add("@a:x");
    expect((await cache.get("@a:x", forceRefresh: true))!["displayname"], "A");
  });

  test("least recently used entry is dropped", () async {
    final cache = makeCache(maxEntries: 2);
    await cache.get("@a:x");
    await cache.get("@b:x");
    await cache.get("@a:x"); // touch a
    await cache.get("@c:x");
    expect(cache.peek("@b:x"), isNull);
    expect(cache.peek("@a:x"), isNotNull);
    expect(cache.peek("@c:x"), isNotNull);
  });

  test("no more than maxConcurrent requests run at once", () async {
    var running = 0;
    var peak = 0;
    final gates = <Completer<void>>[];
    final cache = ProfileFieldCache((userId) async {
      running++;
      if (running > peak) peak = running;
      final gate = Completer<void>();
      gates.add(gate);
      await gate.future;
      running--;
      return {"displayname": userId};
    }, maxConcurrent: 2);

    final all = Future.wait(List.generate(5, (i) => cache.get("@u$i:x")));
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
      while (gates.isNotEmpty) {
        gates.removeAt(0).complete();
        await Future<void>.delayed(Duration.zero);
      }
    }
    final results = await all;
    expect(results.length, 5);
    expect(peak, 2);
  });
}
