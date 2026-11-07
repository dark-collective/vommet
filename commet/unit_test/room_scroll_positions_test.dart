import 'dart:ui';

import 'package:commet/ui/molecules/room_timeline_widget/room_scroll_positions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const viewport = Rect.fromLTRB(0, 100, 400, 700);

  tearDown(RoomScrollPositions.clear);

  test('picks the lowest event on screen', () {
    final anchor = RoomScrollPositions.anchorFor(viewport, [
      ("\$above", const Rect.fromLTRB(0, 0, 400, 90)),
      ("\$top", const Rect.fromLTRB(0, 90, 400, 300)),
      ("\$low", const Rect.fromLTRB(0, 500, 400, 650)),
      ("\$below", const Rect.fromLTRB(0, 710, 400, 800)),
    ]);
    expect(anchor?.eventId, "\$low");
    expect(anchor?.gapToBottom, 50);
  });

  test('an event reaching past the bottom gives a negative gap', () {
    final anchor = RoomScrollPositions.anchorFor(viewport, [
      ("\$a", const Rect.fromLTRB(0, 400, 400, 600)),
      ("\$b", const Rect.fromLTRB(0, 600, 400, 760)),
    ]);
    expect(anchor?.eventId, "\$b");
    expect(anchor?.gapToBottom, -60);
  });

  test('skips empty rows and returns null when nothing shows', () {
    expect(
        RoomScrollPositions.anchorFor(viewport, [
          ("\$hidden", const Rect.fromLTRB(0, 650, 400, 650)),
          ("\$off", const Rect.fromLTRB(0, 800, 400, 900)),
        ]),
        isNull);
  });

  test('positions are kept per account and room', () {
    final a = RoomScrollPositions.key("acct1", "!room:x");
    final b = RoomScrollPositions.key("acct2", "!room:x");
    RoomScrollPositions.save(a, const RoomScrollPosition("\$e", 12));
    expect(RoomScrollPositions.get(a)?.eventId, "\$e");
    expect(RoomScrollPositions.get(b), isNull);
    RoomScrollPositions.forget(a);
    expect(RoomScrollPositions.get(a), isNull);
  });
}
