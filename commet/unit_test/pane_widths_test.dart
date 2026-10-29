import 'package:commet/config/preferences/double_preference.dart';
import 'package:commet/config/preferences/preference.dart';
import 'package:commet/ui/layout/pane_widths.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  test("knows when a drag pulls well past the narrowest width", () {
    final p = pane();
    p.drag(-(250 - p.min) - PaneWidth.collapsePull + 1);
    expect(p.value, p.min);
    expect(p.pulledPastMin.value, isFalse);
    p.drag(-2);
    expect(p.pulledPastMin.value, isTrue);
    p.drag(10); // back out
    expect(p.pulledPastMin.value, isFalse);
  });

  test("a drag that collapses the pane keeps the width it started at", () {
    final p = pane();
    p.drag(30);
    p.save();
    p.drag(-1000);
    expect(p.pulledPastMin.value, isTrue);
    p.endCollapsed();
    expect(p.value, 280);
    expect(p.pulledPastMin.value, isFalse);
  });

  // Vommet issue 747: the Media tab's width is a share of the room's area.
  group("share of the area", () {
    late PaneWidth seed;
    late SharePaneWidth media;

    setUp(() async {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});
      Preference.preferences = await SharedPreferences.getInstance();
      seed = PaneWidth(DoublePreference("test_seed", defaultValue: 250),
          resizableWhen: () => true);
      media =
          SharePaneWidth(DoublePreference("test_share", defaultValue: 0), seed)
            ..area = 1600;
    });

    tearDown(() => Preference.preferences = null);

    test("follows the other pane's pixels until dragged", () async {
      seed.drag(50);
      await seed.save();
      expect(media.effective, 300);
      media.area = 800;
      expect(media.effective, 300);
    });

    test("a dragged width scales with the area", () async {
      media.drag(150); // 400 of 1600
      await media.save();
      expect(media.effective, 400);
      media.area = 800;
      expect(media.effective, closeTo(200, 1e-9));
      expect(seed.effective, 250, reason: "the other pane keeps its pixels");
    });

    test("stays within its limits when scaled", () async {
      media.drag(150);
      await media.save();
      media.area = 400;
      expect(media.effective, media.min);
      media.area = 4000;
      expect(media.effective, media.max);
    });

    test("a drag starts from the width shown", () async {
      media.drag(150);
      await media.save();
      media.area = 800; // 200 shown
      media.drag(20);
      expect(media.effective, closeTo(220, 1e-9));
      await media.save();
      media.area = 1600;
      expect(media.effective, closeTo(440, 1e-9));
    });

    test("reset returns to the default and tells the layout", () async {
      media.drag(150);
      await media.save();
      media.area = 800;
      var calls = 0;
      media.addListener(() => calls++);
      await media.reset();
      expect(media.effective, 250);
      expect(calls, greaterThan(0));
    });
  });
}
