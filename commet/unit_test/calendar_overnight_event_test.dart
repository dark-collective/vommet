import 'package:calendar_view/calendar_view.dart';
import 'package:commet_calendar_widget/calendar.dart';
import 'package:commet_calendar_widget/rfc8984.dart';
import 'package:test/test.dart';

// Vommet issue 320: events that run past midnight are split in to one block
// per day; every block must sit on its own day, keep the plain title and
// repeat with the event.
RFC8984CalendarEvent overnight(DateTime start, {List<String>? byDay}) {
  return RFC8984CalendarEvent(
    uid: "overnight-uid",
    updated: DateTime.utc(2026, 1, 1),
    title: "Night shift",
    start: start,
    duration: const Duration(hours: 4),
    recurrenceRules: byDay == null
        ? null
        : [
            RFC8984RecurrenceRule(
              frequency: "weekly",
              byDay: byDay.map((d) => Rfc8984NDay(d)).toList(),
            ),
          ],
  );
}

List<String> titlesOn(
    EventController<MatrixCalendarEventState> controller, DateTime day) {
  return controller
      .getEventsOnDay(day)
      .map((e) => "${e.title} ${e.startTime!.hour}")
      .toList();
}

void main() {
  test('one-off overnight event shows a block on each day', () {
    // Thursday 2026-01-01 23:00 to Friday 03:00
    var start = DateTime(2026, 1, 1, 23);
    var blocks = MatrixCalendar.blocksFromRfcEvent(overnight(start), start);

    expect(blocks.length, 2);
    expect(blocks.map((b) => b.title), everyElement("Night shift"));

    var controller = EventController<MatrixCalendarEventState>()
      ..addAll(blocks);
    expect(titlesOn(controller, DateTime(2026, 1, 1)), ["Night shift 23"]);
    expect(titlesOn(controller, DateTime(2026, 1, 2)), ["Night shift 0"]);
    expect(titlesOn(controller, DateTime(2026, 1, 3)), isEmpty);
  });

  test('weekly overnight event repeats the after-midnight block', () {
    // Friday 2026-01-02 23:00 to Saturday 03:00, every Friday and Saturday
    var start = DateTime(2026, 1, 2, 23);
    var blocks = MatrixCalendar.blocksFromRfcEvent(
        overnight(start, byDay: ["fr", "sa"]), start);

    var controller = EventController<MatrixCalendarEventState>()
      ..addAll(blocks);

    for (var week = 0; week < 3; week++) {
      var friday = DateTime(2026, 1, 2 + week * 7);
      var saturday = DateTime(2026, 1, 3 + week * 7);
      var sunday = DateTime(2026, 1, 4 + week * 7);
      expect(titlesOn(controller, friday), ["Night shift 23"],
          reason: "week $week friday");
      expect(
          titlesOn(controller, saturday), ["Night shift 0", "Night shift 23"],
          reason: "week $week saturday");
      expect(titlesOn(controller, sunday), ["Night shift 0"],
          reason: "week $week sunday");
    }
  });

  test('weekdays follow a start that lands on the next day in local time', () {
    // Friday 23:00 in the event's zone is Saturday 01:00 here
    var event = overnight(DateTime(2026, 1, 2, 23), byDay: ["fr"]);
    var blocks =
        MatrixCalendar.blocksFromRfcEvent(event, DateTime(2026, 1, 3, 1));

    expect(blocks.length, 1);
    expect(blocks.single.recurrenceSettings!.weekdays, [5]);
  });

  test('weekly rule without days repeats on the block\'s own weekday', () {
    var start = DateTime(2026, 1, 2, 23);
    var event = overnight(start)
      ..recurrenceRules = [RFC8984RecurrenceRule(frequency: "weekly")];
    var blocks = MatrixCalendar.blocksFromRfcEvent(event, start);

    expect(blocks[0].recurrenceSettings!.weekdays, [4]);
    expect(blocks[1].recurrenceSettings!.weekdays, [5]);
  });
}
