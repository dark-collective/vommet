import 'package:commet/config/preferences/double_preference.dart';
import 'package:commet/ui/layout/pane_widths.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  PaneWidth pane() =>
      PaneWidth(DoublePreference("test_pane", defaultValue: 250));

  test("starts at the default", () {
    expect(pane().value, 250);
  });

  test("drags within its limits", () {
    final p = pane();
    p.drag(40);
    expect(p.value, 290);
    p.save();
    p.drag(-1000);
    expect(p.value, p.min);
    p.drag(5000);
    expect(p.value, p.max);
  });

  test("reset returns to the default", () async {
    final p = pane();
    p.drag(100);
    await p.reset();
    expect(p.value, 250);
  });

  test("notifies listeners while dragging", () {
    final p = pane();
    var calls = 0;
    p.addListener(() => calls++);
    p.drag(30);
    p.drag(30);
    expect(calls, 2);
  });

  test("sticks to the default near it, and pulls back out", () async {
    final p = pane();
    p.drag(60);
    expect(p.value, 310);
    p.drag(-55); // 255: inside the snap zone
    expect(p.value, 250);
    p.drag(-3); // 252: still snapped
    expect(p.value, 250);
    p.drag(-20); // 232: out the other side
    expect(p.value, 232);
    p.drag(25); // 257: back in
    expect(p.value, 250);
    await p.save();
    expect(p.value, 250);
  });
}
