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
}
