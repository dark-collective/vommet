import 'package:commet/ui/molecules/timezone_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz_data;

void main() {
  setUpAll(tz_data.initializeTimeZones);

  // A summer instant: Berlin is CEST (UTC+2), New York EDT (UTC−4).
  final summer = DateTime.utc(2026, 7, 1, 12);

  test("formats offsets", () {
    expect(TimezoneOptions.formatOffset(Duration.zero), "UTC");
    expect(TimezoneOptions.formatOffset(const Duration(hours: 2)), "UTC+2");
    expect(TimezoneOptions.formatOffset(const Duration(hours: -4)), "UTC−4");
    expect(TimezoneOptions.formatOffset(const Duration(hours: 5, minutes: 30)),
        "UTC+5:30");
    expect(
        TimezoneOptions.formatOffset(const Duration(hours: -9, minutes: -30)),
        "UTC−9:30");
  });

  test("lists named zones, without Etc/ ids", () {
    final all = TimezoneOptions.all(now: summer);
    final ids = all.map((o) => o.id).toSet();
    expect(ids, containsAll(["Europe/Berlin", "America/New_York"]));
    expect(ids.any((id) => id.startsWith("Etc/")), isFalse);
    final berlin = all.firstWhere((o) => o.id == "Europe/Berlin");
    expect(berlin.offset, const Duration(hours: 2));
    expect(berlin.city, "Berlin");
    expect(berlin.region, "Europe");
  });

  test("search by city, region, offset and abbreviation", () {
    final all = TimezoneOptions.all(now: summer);
    List<String> ids(String q) =>
        TimezoneOptions.filter(all, q).map((o) => o.id).toList();

    expect(ids("ber").first, "Europe/Berlin");
    expect(ids("new york"), contains("America/New_York"));
    expect(ids("europe berlin"), ["Europe/Berlin"]);
    expect(ids("utc-4"), contains("America/New_York"));
    expect(ids("UTC−4"), contains("America/New_York"));
    expect(ids("gmt+2"), contains("Europe/Berlin"));
    expect(ids("utc+2"), isNot(contains("America/New_York")));
    expect(ids("cest"), contains("Europe/Berlin"));
    expect(ids(""), hasLength(all.length));
    expect(ids("zzzz"), isEmpty);
  });

  test("byId", () {
    expect(TimezoneOptions.byId("America/New_York", now: summer)?.offset,
        const Duration(hours: -4));
    expect(TimezoneOptions.byId("Not/AZone"), isNull);
  });
}
