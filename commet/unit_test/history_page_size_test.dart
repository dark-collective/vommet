// Vommet issue 354: history pages that fold into nothing (only joins, leaves
// and name changes) make the next request bigger, so a room full of server
// events reaches its real messages in a few round trips instead of dozens.

import 'package:commet/client/matrix/history_page_size.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('starts at the normal page size', () {
    expect(HistoryPageSize().current, HistoryPageSize.normal);
  });

  test('each page that shows nothing doubles the next, up to the cap', () {
    final size = HistoryPageSize();
    final seen = <int>[];
    for (var i = 0; i < 6; i++) {
      size.noteShowedSomething(false);
      seen.add(size.current);
    }
    expect(seen, [60, 120, 240, 240, 240, 240]);
  });

  test('a page that shows a message goes back to the normal size', () {
    final size = HistoryPageSize()
      ..noteShowedSomething(false)
      ..noteShowedSomething(false)
      ..noteShowedSomething(true);
    expect(size.current, HistoryPageSize.normal);
  });

  test('an empty page list counts as showing nothing', () {
    final size = HistoryPageSize()..notePage(const []);
    expect(size.current, 60);
  });
}
