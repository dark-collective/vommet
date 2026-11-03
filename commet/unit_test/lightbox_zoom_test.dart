import 'package:commet/ui/atoms/lightbox_zoom.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group("nextZoomStep", () {
    test("steps up and down through the list", () {
      expect(nextZoomStep(1, 1), 1.25);
      expect(nextZoomStep(1.5, 1), 2);
      expect(nextZoomStep(2, -1), 1.5);
      expect(nextZoomStep(1.25, -1), 1);
    });

    test("stops at the ends", () {
      expect(nextZoomStep(3.5, 1), 3.5);
      expect(nextZoomStep(1, -1), 1);
    });

    test("a zoom between steps goes to the nearest step that way", () {
      expect(nextZoomStep(1.7, 1), 2);
      expect(nextZoomStep(1.7, -1), 1.5);
      expect(nextZoomStep(1.999, 1), 2.5);
    });
  });

  group("zoomMatrix", () {
    const viewport = Size(400, 300);

    Offset apply(Matrix4 m, Offset p) => MatrixUtils.transformPoint(m, p);

    test("keeps the clicked point under the pointer", () {
      const point = Offset(150, 120);
      final m = zoomMatrix(
          scenePoint: point, focal: point, scale: 2, viewport: viewport);
      expect(m.getMaxScaleOnAxis(), 2);
      expect(apply(m, point), point);
    });

    test("never leaves an empty band at the edges", () {
      // Zooming around the top-left corner can't pan past it.
      final m = zoomMatrix(
          scenePoint: const Offset(10, 10),
          focal: const Offset(200, 150),
          scale: 2,
          viewport: viewport);
      expect(apply(m, Offset.zero), Offset.zero);

      final far = zoomMatrix(
          scenePoint: const Offset(395, 295),
          focal: const Offset(200, 150),
          scale: 2,
          viewport: viewport);
      expect(apply(far, const Offset(400, 300)), const Offset(400, 300));
    });

    test("fit is the identity", () {
      final m = zoomMatrix(
          scenePoint: const Offset(50, 60),
          focal: const Offset(200, 150),
          scale: 1,
          viewport: viewport);
      expect(m, Matrix4.identity());
    });

    test("clamps to the viewer's range", () {
      final m = zoomMatrix(
          scenePoint: const Offset(200, 150),
          focal: const Offset(200, 150),
          scale: 10,
          viewport: viewport);
      expect(m.getMaxScaleOnAxis(), maxZoom);
    });
  });
}
