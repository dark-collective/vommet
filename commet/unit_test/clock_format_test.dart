// Vommet: the 12/24-hour clock setting (Vommet issue 347).

import 'package:commet/main.dart';
import 'package:commet/utils/clock_format.dart';
import 'package:commet/utils/text_utils.dart';
import 'package:commet_calendar_widget/hour_label.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final t = DateTime(2026, 10, 9, 16, 5, 9);

  setUpAll(() async {
    await initializeDateFormatting();
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });

  test("parse falls back to the system default", () {
    expect(ClockFormat.parse("twelveHour"), ClockStyle.twelveHour);
    expect(ClockFormat.parse("twentyFourHour"), ClockStyle.twentyFourHour);
    expect(ClockFormat.parse("system"), ClockStyle.system);
    expect(ClockFormat.parse("nonsense"), ClockStyle.system);
    expect(ClockFormat.parse(null), ClockStyle.system);
  });

  test("resolve: system follows the platform, the others are fixed", () {
    for (final sys in [true, false]) {
      expect(ClockFormat.resolve(ClockStyle.system, systemUses24: sys), sys);
      expect(
          ClockFormat.resolve(ClockStyle.twelveHour, systemUses24: sys), false);
      expect(ClockFormat.resolve(ClockStyle.twentyFourHour, systemUses24: sys),
          true);
    }
  });

  test("which languages are on the 24-hour clock", () {
    expect(ClockFormat.localeUses24("en_US"), isFalse);
    expect(ClockFormat.localeUses24("ko"), isFalse);
    expect(ClockFormat.localeUses24("de"), isTrue);
    expect(ClockFormat.localeUses24("en_GB"), isTrue);
  });

  test("time on each clock", () {
    String f(bool use24, String locale, {bool seconds = false}) =>
        ClockFormat.time(use24: use24, seconds: seconds, locale: locale)
            .format(t);

    expect(f(true, "en_US"), "16:05");
    expect(f(false, "en_US"), "4:05 PM");
    expect(f(true, "en_US", seconds: true), "16:05:09");
    expect(f(false, "en_US", seconds: true), "4:05:09 PM");
    // 12-hour chosen in a 24-hour language still gives AM/PM.
    expect(f(false, "de"), "4:05 PM");
    expect(f(true, "de"), "16:05");
    // A 12-hour language keeps its own order.
    expect(f(false, "ko"), DateFormat.jm("ko").format(t));
  });

  test("date and time", () {
    expect(
        ClockFormat.dateAndTime(DateFormat.yMMMMd("en_US"),
                use24: true, seconds: true)
            .format(t),
        "October 9, 2026 16:05:09");
    expect(
        ClockFormat.dateAndTime(DateFormat.yMMMMd("en_US"),
                use24: false, seconds: true)
            .format(t),
        "October 9, 2026 4:05:09 PM");
  });

  Future<BuildContext> pumpScope(WidgetTester tester,
      {required bool platform24}) async {
    late BuildContext ctx;
    // What the engine reports for the OS setting.
    await tester.pumpWidget(MediaQuery(
        data: MediaQueryData(alwaysUse24HourFormat: platform24),
        child: MaterialApp(
            builder: (context, child) => ClockFormatScope(child: child!),
            home: Builder(builder: (c) {
              ctx = c;
              return const SizedBox();
            }))));
    return ctx;
  }

  testWidgets("the setting reaches MediaQuery and the formatters",
      (tester) async {
    await preferences.clockFormat.set("system");
    var ctx = await pumpScope(tester, platform24: true);
    expect(ClockFormat.use24Of(ctx), isTrue);
    expect(ClockFormat.timeOf(ctx, t), "16:05");

    ctx = await pumpScope(tester, platform24: false);
    expect(ClockFormat.use24Of(ctx), isFalse);
    expect(ClockFormat.timeOf(ctx, t), "4:05 PM");

    await preferences.clockFormat.set("twentyFourHour");
    // The change event is delivered outside the test's fake clock.
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();
    expect(ClockFormat.use24Of(ctx), isTrue,
        reason: "changing the setting rebuilds below the scope");
    expect(ClockFormat.timeOf(ctx, t), "16:05");
    expect(TextUtils.dividerLabel(t, ctx, now: t), "Today, 16:05");
    expect(TextUtils.timestampToLocalizedTimeSpecific(t, ctx),
        "October 9, 2026 16:05:09");

    await preferences.clockFormat.set("twelveHour");
    ctx = await pumpScope(tester, platform24: true);
    expect(ClockFormat.use24Of(ctx), isFalse);
    expect(TextUtils.dividerLabel(t, ctx, now: t), "Today, 4:05 PM");

    await preferences.clockFormat.set("system");
  });

  testWidgets("calendar hour marks follow the clock", (tester) async {
    final onePm = DateTime(2026, 10, 9, 13);
    await preferences.clockFormat.set("twentyFourHour");
    var ctx = await pumpScope(tester, platform24: false);
    expect(calendarHourLabel(ctx, onePm), "13:00");

    await preferences.clockFormat.set("twelveHour");
    ctx = await pumpScope(tester, platform24: true);
    expect(calendarHourLabel(ctx, onePm), "1 PM");

    await preferences.clockFormat.set("system");
  });
}
