import 'package:commet/debug/log.dart';
import 'package:commet/ui/pages/settings/categories/developer/vommet_log_export.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'log export: header, oldest first, colour codes stripped, counts, traces',
      () {
    final a = LogEntry(LogType.info, "\x1b[32mCall diag: subscribed\x1b[0m");
    final b = LogEntry(LogType.warning, "same thing")..count = 3;
    final c = LogEntryException(LogType.error, "boom", Exception("x"),
        StackTrace.fromString("#0 main (file.dart:1)\n#1 run (file.dart:2)"));
    final text = vommetLogText([a, b, c],
        filter: '"diag"', now: DateTime.utc(2026, 10, 12, 1, 2, 3));

    final lines = text.split("\n");
    expect(lines.first, "Vommet log export");
    expect(text, contains("Entries: 3 (filter: \"diag\")"));
    expect(text, isNot(contains("\x1b")));
    final body = lines.skipWhile((l) => l.isNotEmpty).skip(1).toList();
    expect(body[0], endsWith("[info] Call diag: subscribed"));
    expect(body[1], endsWith("[warning x3] same thing"));
    expect(body[2], endsWith("[error] boom"));
    expect(body[3], "    #0 main (file.dart:1)");
    expect(body[4], "    #1 run (file.dart:2)");
  });

  test('log export file name is timestamped', () {
    expect(vommetLogFileName(DateTime(2026, 10, 12, 21, 41, 26)),
        "vommet-log-20261012-214126.txt");
  });
}
