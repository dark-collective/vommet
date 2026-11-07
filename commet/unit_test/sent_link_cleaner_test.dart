import 'dart:convert';
import 'dart:io';

import 'package:commet/utils/links/sent_link_cleaner.dart';
import 'package:commet/utils/links/tracking_parameters_cleaner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final json =
      jsonDecode(File("assets/data/clearurls.json").readAsStringSync());
  final rules = [
    for (final e in (json["providers"] as Map<String, dynamic>).entries)
      UrlParameterRule.fromJson(e.value as Map<String, dynamic>, e.key)!
  ];
  String clean(String text) => SentLinkCleaner.clean(text, rules);

  test("strips utm parameters and keeps the rest", () {
    expect(clean("see https://example.com/a?id=4&utm_source=x&utm_medium=y"),
        "see https://example.com/a?id=4");
  });

  test("drops the question mark when nothing is left", () {
    expect(clean("https://example.com/page?utm_campaign=z"),
        "https://example.com/page");
  });

  test("strips fbclid and keeps the fragment", () {
    expect(clean("https://example.com/p?fbclid=abc#top"),
        "https://example.com/p#top");
  });

  test("strips YouTube si", () {
    expect(clean("https://youtu.be/dQw4w9WgXcQ?si=AbCdEf"),
        "https://youtu.be/dQw4w9WgXcQ");
  });

  test("leaves clean links and plain text alone", () {
    const text = "hi https://example.com/a?id=4&page=2 there";
    expect(clean(text), text);
    expect(clean("no links here"), "no links here");
  });

  test("keeps trailing punctuation outside the link", () {
    expect(clean("look (https://example.com/?utm_source=a)."),
        "look (https://example.com/).");
  });

  test("leaves links in code alone", () {
    const inline = "`https://example.com/?utm_source=a`";
    const fenced = "```\nhttps://example.com/?utm_source=a\n```";
    expect(clean(inline), inline);
    expect(clean(fenced), fenced);
  });

  test("removes every copy of a repeated key", () {
    expect(clean("https://example.com/?utm_source=a&q=1&utm_source=b"),
        "https://example.com/?q=1");
  });
}
