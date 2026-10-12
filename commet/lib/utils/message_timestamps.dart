import 'dart:convert';

import 'package:intl/intl.dart' as intl;

/// MSC3160 timestamps in messages.
///
/// Sending: the composer accepts Discord's `<t:UNIX>` / `<t:UNIX:STYLE>` and
/// Sable's `$[UNIX]` (seconds since the epoch). Each one becomes
/// `<time datetime="2026-10-08T21:00:00+02:00">…</time>` in `formatted_body`,
/// carrying the sender's own UTC offset as MSC3160 asks. The text inside the
/// element, which is also what goes into `body`, is the sender's local time
/// with its offset, so clients without MSC3160 support still show something
/// unambiguous.
///
/// Receiving: [parseDatetime] reads the `datetime` attribute back; the
/// renderer shows it in the reader's own time zone.
class MessageTimestamps {
  static final RegExp _token =
      RegExp(r'<t:(-?\d{1,13})(?::([tTdDfFR]))?>|\$\[(-?\d{1,13})\]');

  // Tokens inside code are left alone.
  static final RegExp _code = RegExp(r'```[\s\S]*?```|`[^`\n]*`');

  static const String _open = '';
  static const String _close = '';
  static final RegExp _placeholder = RegExp('$_open(\\d+)$_close');

  // DateTime's range is ±8.64e15 ms.
  static const int _maxSeconds = 8640000000000;

  /// Finds the timestamp tokens in [message]. Returns null when there are
  /// none, so the caller can send the message unchanged.
  ///
  /// [offsetAt] gives the sender's UTC offset at an instant (defaults to the
  /// device's time zone, DST-aware); tests pass a fixed one.
  static TimestampExpansion? expand(String message,
      {Duration Function(DateTime utc)? offsetAt}) {
    if (message.contains(_open) || message.contains(_close)) return null;
    offsetAt ??= (utc) => utc.toLocal().timeZoneOffset;

    final elements = <String>[];
    final markdown = StringBuffer();
    final plain = StringBuffer();

    void addText(String text) {
      var last = 0;
      for (final m in _token.allMatches(text)) {
        final seconds = int.tryParse(m[1] ?? m[3]!);
        if (seconds == null || seconds.abs() > _maxSeconds) continue;

        final utc =
            DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
        final offset = offsetAt!(utc);
        final fallback = fallbackText(utc, offset, m[2] ?? 'f');

        final before = text.substring(last, m.start);
        markdown.write(before);
        plain.write(before);
        markdown.write('$_open${elements.length}$_close');
        plain.write(fallback);
        elements.add('<time datetime="${datetimeAttribute(utc, offset)}">'
            '${const HtmlEscape().convert(fallback)}</time>');
        last = m.end;
      }
      final rest = text.substring(last);
      markdown.write(rest);
      plain.write(rest);
    }

    var last = 0;
    for (final code in _code.allMatches(message)) {
      addText(message.substring(last, code.start));
      markdown.write(code[0]);
      plain.write(code[0]);
      last = code.end;
    }
    addText(message.substring(last));

    if (elements.isEmpty) return null;
    return TimestampExpansion._(
        markdown.toString(), plain.toString(), elements);
  }

  /// `2026-10-08T21:00:00+02:00`: the sender's wall-clock time and offset.
  static String datetimeAttribute(DateTime utc, Duration offset) {
    final wall = utc.toUtc().add(offset);
    return intl.DateFormat("yyyy-MM-dd'T'HH:mm:ss", 'en_US').format(wall) +
        formatOffset(offset);
  }

  /// `+02:00`, `-05:30`, `+00:00`.
  static String formatOffset(Duration offset) {
    final sign = offset.isNegative ? '-' : '+';
    final minutes = offset.inMinutes.abs();
    final h = (minutes ~/ 60).toString().padLeft(2, '0');
    final m = (minutes % 60).toString().padLeft(2, '0');
    return '$sign$h:$m';
  }

  /// The sender-side text for a Discord style letter. Relative (`R`) can't
  /// stay relative in a stored message, so it falls back to `f`.
  static String fallbackText(DateTime utc, Duration offset, String style) {
    final wall = utc.toUtc().add(offset);
    String fmt(String pattern) =>
        intl.DateFormat(pattern, 'en_US').format(wall);
    final zone = ' (UTC${formatOffset(offset)})';

    return switch (style) {
      't' => fmt('HH:mm') + zone,
      'T' => fmt('HH:mm:ss') + zone,
      'd' => fmt('yyyy-MM-dd'),
      'D' => fmt('d MMMM yyyy'),
      'F' => fmt('EEEE, d MMMM yyyy HH:mm') + zone,
      _ => fmt('d MMMM yyyy HH:mm') + zone,
    };
  }

  // MSC3160 requires a zone; without one, the instant is unknown.
  static final RegExp _zone =
      RegExp(r'(?:Z|([+-])(\d{2}):?(\d{2}))$', caseSensitive: false);

  /// Parses a `<time datetime>` value. Returns null unless it is a date and
  /// time with an explicit zone.
  static DateTime? parseDatetime(String? value) {
    if (value == null) return null;
    final v = value.trim();
    if (!v.contains('T') && !v.contains('t') && !v.contains(' ')) return null;
    if (!_zone.hasMatch(v)) return null;
    return DateTime.tryParse(v)?.toUtc();
  }

  /// The offset written in a `datetime` value (the sender's zone), if any.
  static Duration? senderOffset(String? value) {
    if (value == null) return null;
    final m = _zone.firstMatch(value.trim());
    if (m == null) return null;
    if (m[1] == null) return Duration.zero;
    final d = Duration(hours: int.parse(m[2]!), minutes: int.parse(m[3]!));
    return m[1] == '-' ? -d : d;
  }

  /// "in 3 hours", "5 minutes ago", "now".
  static String relative(DateTime time, DateTime now) {
    final diff = time.difference(now);
    final s = diff.inSeconds.abs();
    String unit(int n, String name) => n == 1 ? '1 $name' : '$n ${name}s';
    final String amount;
    if (s < 45) {
      return 'now';
    } else if (s < 45 * 60) {
      amount = unit((s / 60).round(), 'minute');
    } else if (s < 22 * 3600) {
      amount = unit((s / 3600).round(), 'hour');
    } else if (s < 26 * 86400) {
      amount = unit((s / 86400).round(), 'day');
    } else if (s < 320 * 86400) {
      amount = unit((s / (30 * 86400)).round(), 'month');
    } else {
      amount = unit((s / (365 * 86400)).round(), 'year');
    }
    return diff.isNegative ? '$amount ago' : 'in $amount';
  }
}

class TimestampExpansion {
  /// The message with each timestamp swapped for a placeholder that markdown
  /// leaves untouched. Run markdown on this, then [applyToHtml].
  final String markdownInput;

  /// The message for `body`: each timestamp as its fallback text.
  final String plainBody;

  final List<String> _elements;

  TimestampExpansion._(this.markdownInput, this.plainBody, this._elements);

  String applyToHtml(String html) => html.replaceAllMapped(
      MessageTimestamps._placeholder, (m) => _elements[int.parse(m[1]!)]);
}
