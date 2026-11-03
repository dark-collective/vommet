import 'package:commet/ui/molecules/pinned_message_bar.dart';
import 'package:test/test.dart';

void main() {
  DateTime t(int minute) => DateTime.utc(2026, 10, 15, 12, minute);

  test('room and personal pins merge newest first', () {
    final merged = PinnedBarEntry.merge(
      [PinnedBarEntry("a", t(1)), PinnedBarEntry("c", t(30))],
      [PinnedBarEntry("b", t(10), personal: true)],
    );
    expect(merged.map((e) => e.eventId), ["c", "b", "a"]);
    expect(merged.map((e) => e.personal), [false, true, false]);
  });

  test('a message pinned both ways counts once, as a room pin', () {
    final merged = PinnedBarEntry.merge(
      [PinnedBarEntry("a", t(1))],
      [PinnedBarEntry("a", t(1), personal: true)],
    );
    expect(merged.length, 1);
    expect(merged.single.personal, false);
  });

  test('track shows one segment per pin up to four', () {
    expect(PinnedBarEntry.track(0, 1), (segments: 1, lit: 0));
    expect(PinnedBarEntry.track(2, 3), (segments: 3, lit: 2));
  });

  test('track pages through more than four pins', () {
    expect(PinnedBarEntry.track(0, 10), (segments: 4, lit: 0));
    expect(PinnedBarEntry.track(5, 10), (segments: 4, lit: 1));
    // The last page is pulled back so it stays full.
    expect(PinnedBarEntry.track(9, 10), (segments: 4, lit: 3));
  });
}
