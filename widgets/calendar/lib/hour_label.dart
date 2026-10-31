import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

/// Vommet: the hour marks beside the day and week views, on the app's clock
/// (MediaQuery.alwaysUse24HourFormat, set by Vommet's clock setting; Vommet
/// issue 347). calendar_view's own marks are always "1 pm".
String calendarHourLabel(BuildContext context, DateTime date) {
  if (MediaQuery.alwaysUse24HourFormatOf(context)) {
    return DateFormat.Hm().format(date);
  }
  final own = DateFormat.j();
  final pattern = own.pattern ?? "";
  // A 24-hour language: spell out the 12-hour clock.
  if (pattern.contains("H") || pattern.contains("k")) {
    return DateFormat("h a").format(date);
  }
  // CLDR's narrow no-break space before AM/PM is missing from some fonts.
  return DateFormat(pattern.replaceAll("\u202f", " ")).format(date);
}
