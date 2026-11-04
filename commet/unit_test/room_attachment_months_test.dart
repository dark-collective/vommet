import 'package:commet/ui/organisms/room_members_list/room_attachments.dart';
import 'package:flutter_test/flutter_test.dart';

// Vommet issue 602 follow-up: Media, Files and Links share one month grouping.

void main() {
  final times = [
    DateTime(2026, 10, 22, 9),
    DateTime(2026, 10, 1),
    DateTime(2026, 9, 30, 23),
    DateTime(2025, 9, 12),
  ];

  test("groups newest-first entries under their month, in order", () {
    final groups = groupByMonth(times, (t) => t);
    expect(groups.map((g) => g.$1).toList(),
        [DateTime(2026, 10), DateTime(2026, 9), DateTime(2025, 9)]);
    expect(groups.map((g) => g.$2.length).toList(), [2, 1, 1]);
    // Every entry once, in the original order.
    expect(groups.expand((g) => g.$2).toList(), times);
  });

  test("monthRows puts each month before its entries", () {
    expect(monthRows(times, (t) => t), [
      DateTime(2026, 10),
      times[0],
      times[1],
      DateTime(2026, 9),
      times[2],
      DateTime(2025, 9),
      times[3],
    ]);
  });

  test("no entries, no headers", () {
    expect(groupByMonth(<DateTime>[], (t) => t), isEmpty);
    expect(monthRows(<DateTime>[], (t) => t), isEmpty);
  });
}
