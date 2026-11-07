// Vommet: the 12-hour or 24-hour clock for every time the app shows
// (Vommet issue 347). Settings › Appearance › Clock picks System default,
// 12-hour or 24-hour. [ClockFormatScope] sits above the app's Navigator and
// sets MediaQuery's alwaysUse24HourFormat to the result, so code that reads
// that flag (and Flutter's own time pickers) follows the setting. Formatters
// should go through [ClockFormat.time] / [ClockFormat.dateAndTime] so an
// explicit 12-hour choice also holds in a language whose clock is 24-hour.
//
// System default trusts what the engine reports: Android, iOS and macOS read
// the OS setting, Windows the user's time format, Linux GNOME's clock-format
// through the desktop portal (24-hour when the desktop doesn't say). The web
// engine reports nothing, so there the app language decides.

import 'package:commet/main.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart' as intl;

enum ClockStyle { system, twelveHour, twentyFourHour }

class ClockFormat {
  static ClockStyle parse(String? value) => ClockStyle.values
      .firstWhere((s) => s.name == value, orElse: () => ClockStyle.system);

  static ClockStyle get current => parse(preferences.clockFormat.value);

  /// Whether [style] means the 24-hour clock, given what the system says.
  static bool resolve(ClockStyle style, {required bool systemUses24}) =>
      switch (style) {
        ClockStyle.system => systemUses24,
        ClockStyle.twelveHour => false,
        ClockStyle.twentyFourHour => true,
      };

  /// Whether [locale]'s own short time is on the 24-hour clock.
  static bool localeUses24([String? locale]) {
    final pattern = intl.DateFormat.jm(locale).pattern ?? "";
    return pattern.contains("H") || pattern.contains("k");
  }

  /// Hours and minutes (and [seconds]) on the chosen clock. The 12-hour clock
  /// uses the language's own order ("오후 4:05") unless that language is
  /// 24-hour, then "4:05 PM".
  static intl.DateFormat time(
      {required bool use24, bool seconds = false, String? locale}) {
    if (use24) {
      return seconds ? intl.DateFormat.Hms(locale) : intl.DateFormat.Hm(locale);
    }
    if (!localeUses24(locale)) {
      final own =
          seconds ? intl.DateFormat.jms(locale) : intl.DateFormat.jm(locale);
      // CLDR puts a narrow no-break space before AM/PM, which some fonts
      // lack; MaterialLocalizations (used before) had a plain space.
      return intl.DateFormat(own.pattern!.replaceAll("\u202f", " "), locale);
    }
    return intl.DateFormat(seconds ? "h:mm:ss a" : "h:mm a", locale);
  }

  /// [date] followed by the time on the chosen clock.
  static intl.DateFormat dateAndTime(intl.DateFormat date,
          {required bool use24, bool seconds = false}) =>
      date.addPattern(
          time(use24: use24, seconds: seconds, locale: date.locale).pattern);

  /// Whether [context] shows the 24-hour clock (the setting, resolved).
  static bool use24Of(BuildContext context) =>
      MediaQuery.alwaysUse24HourFormatOf(context);

  /// [t]'s local time on the clock [context] uses.
  static String timeOf(BuildContext context, DateTime t,
          {bool seconds = false}) =>
      time(use24: use24Of(context), seconds: seconds).format(t.toLocal());
}

/// Puts the clock setting into MediaQuery.alwaysUse24HourFormat for
/// everything below it.
class ClockFormatScope extends StatelessWidget {
  const ClockFormatScope({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<String>(
      stream: preferences.clockFormat.onChanged,
      builder: (context, _) {
        final data = MediaQuery.of(context);
        final use24 = ClockFormat.resolve(ClockFormat.current,
            systemUses24: kIsWeb
                ? ClockFormat.localeUses24()
                : data.alwaysUse24HourFormat);
        return MediaQuery(
            data: data.copyWith(alwaysUse24HourFormat: use24), child: child);
      },
    );
  }
}
