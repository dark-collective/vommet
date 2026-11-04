import 'package:commet/ui/organisms/room_members_list/media_grid_zoom.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("Media thumbnail size steps up and down through the sizes", () {
    expect(MediaGridZoom.step(110, 1), 140);
    expect(MediaGridZoom.step(110, -1), 96);
  });

  test("Media thumbnail size stays within the smallest and biggest", () {
    expect(MediaGridZoom.step(MediaGridZoom.sizes.first, -1),
        MediaGridZoom.sizes.first);
    expect(MediaGridZoom.step(MediaGridZoom.sizes.last, 1),
        MediaGridZoom.sizes.last);
  });

  test("a size between two steps moves from the nearest one", () {
    expect(MediaGridZoom.step(115, 1), 140);
    expect(MediaGridZoom.step(1000, -1), 280);
  });

  // Vommet issue 649: a pinch settles on the nearest size when it ends.
  test("a pinch settles on the size nearest to what it showed", () {
    expect(MediaGridZoom.settle(110, 1), 110);
    expect(MediaGridZoom.settle(110, 2), 230);
    expect(MediaGridZoom.settle(110, 0.8), 96);
  });

  test("a small pinch keeps the size; past the threshold it steps", () {
    expect(MediaGridZoom.settle(110, 1.1), 110);
    expect(MediaGridZoom.settle(110, 1.15), 140);
    expect(MediaGridZoom.settle(110, 1 / 1.15), 96);
    expect(MediaGridZoom.settle(320, 1.3), 320);
  });

  test("tile width follows the grid's column count", () {
    expect(MediaGridZoom.tileWidth(110, 304), closeTo(98.67, 0.01));
    expect(MediaGridZoom.tileWidth(110, 0), 110);
  });

  // Vommet issue 682: mid-pinch, the grid re-lays out as soon as the pinch
  // passes a size step, to what letting go would settle on.
  test("a pinch re-lays out once it passes the next size", () {
    expect(MediaGridZoom.live(110, 110, 1.1), 110);
    expect(MediaGridZoom.live(110, 110, 1.25), 140);
    expect(MediaGridZoom.live(110, 140, 2), 230);
    expect(MediaGridZoom.live(110, 110, 0.8), 96);
  });

  test("a pinch resting on a size boundary doesn't flicker", () {
    // Just past the step: stays at the bigger size until well back.
    expect(MediaGridZoom.live(110, 140, 1.12), 140);
    expect(MediaGridZoom.live(110, 140, 1.05), 110);
    // Just short of the step from the smaller size: no change yet.
    expect(MediaGridZoom.live(110, 110, 1.17), 110);
    expect(MediaGridZoom.live(110, 110, 1.22), 140);
  });

  test("a live layout matches what the pinch settles on away from a boundary",
      () {
    for (final scale in [0.5, 0.7, 0.85, 1.0, 1.4, 1.8, 2.5, 3.0]) {
      final settled = MediaGridZoom.settle(110, scale);
      expect(MediaGridZoom.live(110, 110, scale), settled, reason: "$scale");
      expect(MediaGridZoom.live(110, settled, scale), settled,
          reason: "$scale");
    }
  });

  // Vommet issue 897: the sticker picker steps by stickers per row; see
  // unit_test/sticker_picker_columns_test.dart.
  test("the sticker picker's sizes bound what a sticker may be", () {
    expect(GridZoom.stickers.fixedCount, isTrue);
    expect(GridZoom.stickers.sizes, [64, 280]);
  });
}
