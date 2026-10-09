import 'package:commet/utils/message_timestamps.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: implementation_imports
import 'package:matrix/src/utils/markdown.dart' as mx_markdown;

void main() {
  const plus2 = Duration(hours: 2);
  Duration fixed(DateTime _) => plus2;

  // 2023-11-14T22:13:20Z
  const unix = 1700000000;

  test('no tokens leaves the message alone', () {
    expect(MessageTimestamps.expand('hello <b>', offsetAt: fixed), isNull);
    expect(MessageTimestamps.expand(r'costs $[5 apples]', offsetAt: fixed),
        isNull);
  });

  test('Discord token becomes a <time> element and a plain fallback', () {
    final e =
        MessageTimestamps.expand('call at <t:$unix:t>?', offsetAt: fixed)!;
    expect(e.plainBody, 'call at 00:13 (UTC+02:00)?');
    expect(
        e.applyToHtml(e.markdownInput),
        'call at <time datetime="2023-11-15T00:13:20+02:00">'
        '00:13 (UTC+02:00)</time>?');
  });

  test('Sable token and default style', () {
    final e = MessageTimestamps.expand('at \$[$unix]', offsetAt: fixed)!;
    expect(e.plainBody, 'at 15 November 2023 00:13 (UTC+02:00)');
  });

  test('every Discord style has a fallback', () {
    String body(String style) =>
        MessageTimestamps.expand('<t:$unix:$style>', offsetAt: fixed)!
            .plainBody;
    expect(body('T'), '00:13:20 (UTC+02:00)');
    expect(body('d'), '2023-11-15');
    expect(body('D'), '15 November 2023');
    expect(body('F'), 'Wednesday, 15 November 2023 00:13 (UTC+02:00)');
    expect(body('R'), '15 November 2023 00:13 (UTC+02:00)');
  });

  test('tokens inside code are left alone', () {
    final e = MessageTimestamps.expand(
        'type `<t:$unix>` to get <t:$unix:d>\n```\n\$[$unix]\n```',
        offsetAt: fixed)!;
    expect(
        e.plainBody, 'type `<t:$unix>` to get 2023-11-15\n```\n\$[$unix]\n```');
  });

  test('negative offsets and out-of-range values', () {
    final e = MessageTimestamps.expand('<t:$unix:t> <t:9999999999999>',
        offsetAt: (_) => const Duration(hours: -5, minutes: -30))!;
    expect(e.plainBody, '16:43 (UTC-05:30) <t:9999999999999>');
    expect(e.applyToHtml(e.markdownInput),
        contains('datetime="2023-11-14T16:43:20-05:30"'));
  });

  test('placeholders survive the SDK markdown step', () {
    final e = MessageTimestamps.expand('**meet** at <t:$unix:t>, ok?',
        offsetAt: fixed)!;
    expect(
        e.applyToHtml(mx_markdown.markdown(e.markdownInput)),
        '<strong>meet</strong> at <time datetime="2023-11-15T00:13:20+02:00">'
        '00:13 (UTC+02:00)</time>, ok?');
  });

  test('parses MSC3160 datetime values', () {
    final utc = DateTime.utc(2021, 4, 30, 11);
    expect(MessageTimestamps.parseDatetime('2021-04-30T09:00-0200'), utc);
    expect(MessageTimestamps.parseDatetime('2021-04-30T13:00:00+02:00'), utc);
    expect(MessageTimestamps.parseDatetime('2021-04-30T11:00:00Z'), utc);
    // No zone, or no time: the instant is unknown.
    expect(MessageTimestamps.parseDatetime('2021-04-30T11:00'), isNull);
    expect(MessageTimestamps.parseDatetime('2021-04-30'), isNull);
    expect(MessageTimestamps.parseDatetime('garbage+0200'), isNull);
    expect(MessageTimestamps.senderOffset('2021-04-30T09:00-0200'),
        const Duration(hours: -2));
  });

  test('relative wording', () {
    final now = DateTime.utc(2026, 10, 7, 12);
    expect(MessageTimestamps.relative(now, now), 'now');
    expect(MessageTimestamps.relative(now.add(const Duration(hours: 3)), now),
        'in 3 hours');
    expect(
        MessageTimestamps.relative(
            now.subtract(const Duration(minutes: 1)), now),
        '1 minute ago');
    expect(MessageTimestamps.relative(now.add(const Duration(days: 2)), now),
        'in 2 days');
  });
}
