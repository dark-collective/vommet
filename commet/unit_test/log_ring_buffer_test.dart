import 'package:commet/debug/log.dart';
import 'package:test/test.dart';

void main() {
  setUp(() => Log.log.clear());

  test("log keeps only the newest maxEntries entries", () {
    for (var i = 0; i < Log.maxEntries + 10; i++) {
      Log.add(LogEntry(LogType.info, "line $i"));
    }

    expect(Log.log.length, Log.maxEntries);
    expect(Log.log.first.rawContent, "line 10");
    expect(Log.log.last.rawContent, "line ${Log.maxEntries + 9}");
  });

  test("repeated lines still merge into one counted entry", () {
    for (var i = 0; i < Log.maxEntries + 10; i++) {
      Log.add(LogEntry(LogType.info, "same"));
    }

    expect(Log.log.length, 1);
    expect(Log.log.single.count, Log.maxEntries + 10);
  });
}
