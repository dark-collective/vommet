import 'package:commet/ui/organisms/message_selection/message_selection.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("a stuck Shift never makes a finger or stylus tap a range", () {
    for (final kind in [PointerDeviceKind.touch, PointerDeviceKind.stylus]) {
      expect(MessageSelection.isShiftClick(kind, shiftPressed: true), isFalse);
    }
    expect(MessageSelection.isShiftClick(null, shiftPressed: true), isFalse);
  });

  test("Shift+click with a mouse or trackpad ticks a range", () {
    for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.trackpad]) {
      expect(MessageSelection.isShiftClick(kind, shiftPressed: true), isTrue);
      expect(MessageSelection.isShiftClick(kind, shiftPressed: false), isFalse);
    }
  });
}
