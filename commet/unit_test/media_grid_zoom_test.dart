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
}
