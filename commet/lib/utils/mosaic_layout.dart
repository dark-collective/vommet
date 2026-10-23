import 'dart:math';

/// One tile of a mosaic, in logical pixels relative to the mosaic's top left.
class MosaicTile {
  final int index;
  final double x, y, width, height;
  const MosaicTile(this.index, this.x, this.y, this.width, this.height);

  @override
  String toString() =>
      "#$index ${width.toStringAsFixed(1)}x${height.toStringAsFixed(1)}"
      " @${x.toStringAsFixed(1)},${y.toStringAsFixed(1)}";
}

class MosaicLayout {
  final List<MosaicTile> tiles;
  final double width, height;
  const MosaicLayout(this.tiles, this.width, this.height);
}

/// Justified-rows layout: items keep their order, each row is scaled to fill
/// [maxWidth], and row breaks are chosen (exhaustively, n is small) so row
/// heights stay close to [targetRowHeight]. Rows taller than [maxRowHeight]
/// are clamped and then don't fill the width. Aspect ratios (width/height)
/// are clamped to [minAspect]..[maxAspect]; tiles crop their image to fit.
class Mosaic {
  static MosaicLayout layout(
    List<double> aspects, {
    required double maxWidth,
    double spacing = 2,
    double targetRowHeight = 160,
    double maxRowHeight = 240,
    double minAspect = 0.5,
    double maxAspect = 2.5,
  }) {
    final n = aspects.length;
    if (n == 0 || maxWidth <= 0) return const MosaicLayout([], 0, 0);

    final a = [
      for (final r in aspects)
        (r.isFinite && r > 0 ? r : 1.0).clamp(minAspect, maxAspect).toDouble()
    ];

    double rowHeight(int from, int to) {
      // items [from, to)
      var sum = 0.0;
      for (var i = from; i < to; i++) {
        sum += a[i];
      }
      return (maxWidth - spacing * (to - from - 1)) / sum;
    }

    double rowCost(int from, int to) {
      final h = rowHeight(from, to);
      final d = h - targetRowHeight;
      // Over-tall rows can't fill the width; make them strongly undesirable.
      final penalty = h > maxRowHeight ? pow(h - maxRowHeight, 2) * 4 : 0;
      return d * d + penalty;
    }

    // best[i] = cheapest layout of the first i items; breakAt[i] = row start.
    final best = List<double>.filled(n + 1, double.infinity);
    final breakAt = List<int>.filled(n + 1, 0);
    best[0] = 0;
    for (var end = 1; end <= n; end++) {
      for (var start = 0; start < end; start++) {
        final c = best[start] + rowCost(start, end);
        if (c < best[end]) {
          best[end] = c;
          breakAt[end] = start;
        }
      }
    }

    final rows = <(int, int)>[];
    for (var end = n; end > 0; end = breakAt[end]) {
      rows.insert(0, (breakAt[end], end));
    }

    final tiles = <MosaicTile>[];
    var y = 0.0;
    var usedWidth = 0.0;
    for (final (from, to) in rows) {
      final h = min(rowHeight(from, to), maxRowHeight);
      var x = 0.0;
      for (var i = from; i < to; i++) {
        final w = a[i] * h;
        tiles.add(MosaicTile(i, x, y, w, h));
        x += w + spacing;
      }
      usedWidth = max(usedWidth, x - spacing);
      y += h + spacing;
    }

    return MosaicLayout(tiles, usedWidth, y - spacing);
  }
}
