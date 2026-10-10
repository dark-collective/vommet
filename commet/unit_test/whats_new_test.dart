// Vommet: the "What's new" changelog and which entries an update shows.

import 'dart:io';

import 'package:commet/utils/whats_new.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sample = '''
{
  "entries": [
    {"date": "2026-10-05T10:00:00Z", "changes": ["Oldest"]},
    {"date": "2026-10-07T10:00:00Z", "changes": ["Newest", "Also newest"]},
    {"date": "2026-10-06T10:00:00Z", "changes": ["Middle"]},
    {"date": "not a date", "changes": ["Dropped"]},
    {"date": "2026-10-04T10:00:00Z", "changes": []},
    "garbage"
  ]
}''';

  final all = WhatsNew.parse(sample);
  DateTime d(String s) => DateTime.parse(s);

  test("parses valid entries, newest first, and skips broken ones", () {
    expect(all.map((e) => e.changes.first), ["Newest", "Middle", "Oldest"]);
    expect(all.first.changes, ["Newest", "Also newest"]);
  });

  test("broken changelog gives no entries instead of failing", () {
    expect(WhatsNew.parse("not json"), isEmpty);
    expect(WhatsNew.parse("{}"), isEmpty);
    expect(WhatsNew.parse('{"entries": 5}'), isEmpty);
  });

  test("an update shows every build since the last one opened", () {
    final shown = WhatsNew.since(
        all, d("2026-10-05T12:00:00Z"), d("2026-10-07T12:00:00Z"));
    expect(shown.map((e) => e.changes.first), ["Newest", "Middle"]);
  });

  test("skipping several builds shows all of them", () {
    final shown = WhatsNew.since(
        all, d("2026-10-01T00:00:00Z"), d("2026-10-07T12:00:00Z"));
    expect(shown.length, 3);
  });

  test("entries newer than this build are not shown", () {
    final shown = WhatsNew.since(
        all, d("2026-10-05T12:00:00Z"), d("2026-10-06T12:00:00Z"));
    expect(shown.map((e) => e.changes.first), ["Middle"]);
  });

  test("nothing new since the last build means nothing to show", () {
    expect(
        WhatsNew.since(
            all, d("2026-10-07T12:00:00Z"), d("2026-10-07T13:00:00Z")),
        isEmpty);
  });

  test("updating from before this feature shows only the newest entry", () {
    final shown = WhatsNew.since(all, null, d("2026-10-07T12:00:00Z"));
    expect(shown.map((e) => e.changes.first), ["Newest"]);
  });

  test("the shipped changelog parses and every entry has changes", () {
    final source = File("assets/data/changelog.json").readAsStringSync();
    final shipped = WhatsNew.parse(source);
    expect(shipped, isNotEmpty);
    for (final e in shipped) {
      expect(e.changes, isNotEmpty);
      expect(e.date.isUtc, isTrue);
    }
  });
}
