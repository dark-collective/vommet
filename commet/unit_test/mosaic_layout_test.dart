import 'package:commet/utils/mosaic_layout.dart';
import 'package:test/test.dart';

void main() {
  List<int> rowSizes(MosaicLayout l) {
    final sizes = <int>[];
    double? y;
    for (final t in l.tiles) {
      if (t.y != y) {
        sizes.add(0);
        y = t.y;
      }
      sizes[sizes.length - 1]++;
    }
    return sizes;
  }

  test("two squares sit side by side", () {
    final l = Mosaic.layout([1, 1], maxWidth: 400);
    expect(rowSizes(l), [2]);
  });

  test("four squares make a 2x2 grid", () {
    final l = Mosaic.layout([1, 1, 1, 1], maxWidth: 400);
    expect(rowSizes(l), [2, 2]);
  });

  test("rows fill the width exactly when not clamped", () {
    final l = Mosaic.layout([1.5, 0.75, 1, 1.33, 0.8], maxWidth: 420);
    double? y;
    var right = 0.0;
    for (final t in l.tiles) {
      if (y != null && t.y != y) {
        expect(right, closeTo(420, 0.01));
      }
      y = t.y;
      right = t.x + t.width;
    }
    expect(l.width, closeTo(420, 0.01));
  });

  test("tiles keep their order and don't overlap", () {
    final l = Mosaic.layout([1, 2, 0.5, 1, 1, 1.7, 0.6], maxWidth: 500);
    expect(l.tiles.map((t) => t.index).toList(), [0, 1, 2, 3, 4, 5, 6]);
    for (var i = 1; i < l.tiles.length; i++) {
      final p = l.tiles[i - 1], c = l.tiles[i];
      if (p.y == c.y) expect(c.x, greaterThan(p.x + p.width));
      if (p.y != c.y) expect(c.y, greaterThan(p.y + p.height));
    }
    expect(l.height, closeTo(l.tiles.last.y + l.tiles.last.height, 0.01));
  });

  test("row height is clamped for very wide rows", () {
    final l = Mosaic.layout([1, 1], maxWidth: 1000, maxRowHeight: 240);
    for (final t in l.tiles) {
      expect(t.height, lessThanOrEqualTo(240));
    }
  });

  test("extreme or missing aspect ratios are tamed", () {
    final l = Mosaic.layout([20, 0.01, double.nan, -1], maxWidth: 400);
    for (final t in l.tiles) {
      final r = t.width / t.height;
      expect(r, inInclusiveRange(0.5 - 1e-9, 2.5 + 1e-9));
    }
  });
}
