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

  test('tokens at the edge of DateTime are left as written', () {
    // 8640000000000 s is DateTime's maximum; adding +2h used to throw.
    expect(
        MessageTimestamps.expand('<t:8640000000000> <t:-8640000000000>',
            offsetAt: fixed),
        isNull);
    final e = MessageTimestamps.expand('<t:253402300799>', offsetAt: fixed)!;
    expect(e.applyToHtml(e.markdownInput),
        contains('datetime="10000-01-01T01:59:59+02:00"'));
    expect(MessageTimestamps.parseDatetime('10000-01-01T01:59:59+02:00'),
        DateTime.utc(9999, 12, 31, 23, 59, 59));
  });

  test('placeholders survive the SDK markdown step', () {
    final e = MessageTimestamps.expand('**meet** at <t:$unix:t>, ok?',
        offsetAt: fixed)!;
    expect(
        e.applyToHtml(mx_markdown.markdown(e.markdownInput)),
        '<strong>meet</strong> at <time datetime="2023-11-15T00:13:20+02:00">'
        '00:13 (UTC+02:00)</time>, ok?');
  });

  // Vommet issue 388: on testing, the send path's markdown step marks
  // __underline__ with U+E000 / U+E001 and turns those into <u> and </u>
  // after markdown. With the same characters as placeholders, a timestamp
  // was sent as <u>0</u>.
  String sendSteps(String input) {
    final marked = input.replaceAllMapped(
        RegExp(r'__(.+?)__'), (m) => '\uE000${m[1]}\uE001');
    return mx_markdown
        .markdown(marked)
        .replaceAll('\uE000', '<u>')
        .replaceAll('\uE001', '</u>');
  }

  for (final token in ['<t:$unix>', '\$[$unix]']) {
    test('$token survives the underline step', () {
      final e = MessageTimestamps.expand('at $token ok', offsetAt: fixed)!;
      expect(
          e.applyToHtml(sendSteps(e.markdownInput)),
          'at <time datetime="2023-11-15T00:13:20+02:00">'
          '15 November 2023 00:13 (UTC+02:00)</time> ok');
    });
  }

  test('a timestamp inside __underline__ keeps both', () {
    final e = MessageTimestamps.expand('__<t:$unix:d>__', offsetAt: fixed)!;
    expect(e.applyToHtml(sendSteps(e.markdownInput)),
        '<u><time datetime="2023-11-15T00:13:20+02:00">2023-11-15</time></u>');
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
    // Out of range: shown as written instead of failing to render.
    expect(MessageTimestamps.parseDatetime('+275760-09-13T05:00:00+05:00'),
        isNull);
    expect(MessageTimestamps.parseDatetime('+275760-09-13T00:00:00Z'), isNull);
    expect(MessageTimestamps.parseDatetime('-000100-01-01T00:00:00Z'), isNull);
    expect(MessageTimestamps.parseDatetime('9999-12-31T23:00:00+05:00'),
        DateTime.utc(9999, 12, 31, 18));
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
