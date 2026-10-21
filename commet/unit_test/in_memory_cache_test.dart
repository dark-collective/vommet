import 'dart:async';

import 'package:commet/utils/in_memory_cache.dart';
import 'package:test/test.dart';

void main() {
  test("expired entries are announced by onRemove", () async {
    final cache = InMemoryCache<int>(
        maxRetention: const Duration(milliseconds: 1),
        pollFrequency: const Duration(milliseconds: 20));
    // clean() counts age in whole seconds, so "a" goes on the first poll
    // after ~1 s. Wait for the event itself rather than a fixed sleep that
    // a loaded machine overruns.
    final removed = cache.onRemove.first;
    cache.put("a", 1);
    expect(await removed.timeout(const Duration(seconds: 20)), "a");
    cache.dispose();
  });

  test("after dispose nothing is announced and the timer stops", () async {
    final cache = InMemoryCache<int>(
        maxRetention: const Duration(milliseconds: 1),
        pollFrequency: const Duration(milliseconds: 20));
    final removed = <String>[];
    final done = Completer<void>();
    cache.onRemove.listen(removed.add, onDone: done.complete);
    cache.put("a", 1);
    cache.dispose();
    await done.future.timeout(const Duration(seconds: 20));
    // Past the point where "a" would have expired, had the timer survived.
    await Future.delayed(const Duration(milliseconds: 1200));
    expect(removed, isEmpty);
  });
}
