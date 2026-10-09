import 'package:commet/utils/in_memory_cache.dart';
import 'package:test/test.dart';

void main() {
  test("expired entries are announced by onRemove", () async {
    final cache = InMemoryCache<int>(
        maxRetention: const Duration(milliseconds: 1),
        pollFrequency: const Duration(milliseconds: 20));
    final removed = <String>[];
    cache.onRemove.listen(removed.add);
    cache.put("a", 1);
    await Future.delayed(const Duration(milliseconds: 1200));
    expect(removed, contains("a"));
    cache.dispose();
  });

  test("after dispose nothing is announced and the timer stops", () async {
    final cache = InMemoryCache<int>(
        maxRetention: const Duration(milliseconds: 1),
        pollFrequency: const Duration(milliseconds: 20));
    final removed = <String>[];
    cache.onRemove.listen(removed.add, onDone: () => removed.add("<done>"));
    cache.put("a", 1);
    cache.dispose();
    await Future.delayed(const Duration(milliseconds: 1200));
    expect(removed, ["<done>"]);
  });
}
