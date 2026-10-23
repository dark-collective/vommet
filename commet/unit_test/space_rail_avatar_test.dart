import 'package:commet/client/matrix/matrix_space.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group("space avatar on the sidebar rail", () {
    test("the 90 px thumbnail is too small for a phone's rail", () {
      // a 56 px icon on a 2.6x phone needs 145 px
      expect(
          MatrixSpace.thumbnailTooSmallForRail(96, 96,
              devicePixelRatio: 2.6, iconSize: 56),
          isTrue);
    });

    test("but sharp enough on a 1x desktop", () {
      expect(
          MatrixSpace.thumbnailTooSmallForRail(96, 96,
              devicePixelRatio: 1, iconSize: 56),
          isFalse);
    });

    test("judged by the shorter side", () {
      expect(
          MatrixSpace.thumbnailTooSmallForRail(200, 96,
              devicePixelRatio: 1.5, iconSize: 64),
          isTrue);
      expect(
          MatrixSpace.thumbnailTooSmallForRail(200, 128,
              devicePixelRatio: 2, iconSize: 64),
          isFalse);
    });
  });
}
