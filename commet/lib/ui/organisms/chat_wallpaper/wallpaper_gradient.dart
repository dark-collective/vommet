import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:commet/client/components/chat_wallpaper/chat_wallpaper_component.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

/// Vommet: a color wallpaper ([WallpaperFill]). One color fills; two make a
/// diagonal gradient; three or four are a four-point gradient, each color
/// strongest at its own point, that can move one step along a ring of
/// points when a message comes or goes. Our own drawing, not ported code.
class WallpaperGradient {
  /// The ring of points the colors sit on, in a unit square (0,0 = top
  /// left). Color i sits on point `step + 2i`, so four colors take every
  /// other point and a step moves each to the next one.
  static const List<Offset> ring = [
    Offset(0.80, 0.10),
    Offset(0.60, 0.20),
    Offset(0.35, 0.25),
    Offset(0.25, 0.60),
    Offset(0.20, 0.90),
    Offset(0.40, 0.80),
    Offset(0.65, 0.75),
    Offset(0.75, 0.40),
  ];

  /// How far a color reaches, in unit-square lengths.
  static const double reach = 0.9;

  /// Where each of [count] colors sits at [phase] (a step, or between two
  /// steps while moving).
  static List<Offset> centers(int count, double phase) {
    final step = phase.floor();
    final t = phase - step;
    return [
      for (var i = 0; i < count; i++)
        Offset.lerp(ring[(step + 2 * i) % ring.length],
            ring[(step + 2 * i + 1) % ring.length], t)!,
    ];
  }

  /// How much each color counts at [point]: nearer is stronger, adding up
  /// to 1. Past every color's [reach], the nearest one alone.
  static List<double> weights(Offset point, List<Offset> centers) {
    final weights = [
      for (final c in centers)
        math.pow(math.max(0.0, reach - (point - c).distance), 4).toDouble(),
    ];
    final sum = weights.fold(0.0, (a, b) => a + b);
    if (sum <= 0) {
      var nearest = 0;
      for (var i = 1; i < centers.length; i++) {
        if ((point - centers[i]).distance <
            (point - centers[nearest]).distance) {
          nearest = i;
        }
      }
      return [for (var i = 0; i < centers.length; i++) i == nearest ? 1 : 0];
    }
    return [for (final w in weights) w / sum];
  }

  /// The gradient's color at [point], with the colors at [centers].
  static Color colorAt(Offset point, List<Color> colors, List<Offset> centers) {
    final w = weights(point, centers);
    var r = 0.0, g = 0.0, b = 0.0;
    for (var i = 0; i < colors.length; i++) {
      r += colors[i].r * w[i];
      g += colors[i].g * w[i];
      b += colors[i].b * w[i];
    }
    return Color.from(alpha: 1, red: r, green: g, blue: b);
  }
}

/// Draws a [WallpaperFill]. With [shifts], each event moves a 3- or 4-color
/// gradient one step (when the fill animates and motion isn't reduced).
class WallpaperFillView extends StatefulWidget {
  const WallpaperFillView({
    required this.fill,
    this.shifts,
    this.wash,
    super.key,
  });

  final WallpaperFill fill;
  final Stream<void>? shifts;

  /// Laid over the colors (messages without bubbles stay readable).
  final Color? wash;

  /// One step's length.
  static const Duration stepDuration = Duration(milliseconds: 500);

  @override
  State<WallpaperFillView> createState() => _WallpaperFillViewState();
}

class _WallpaperFillViewState extends State<WallpaperFillView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _move = AnimationController(
      vsync: this, duration: WallpaperFillView.stepDuration);
  StreamSubscription<void>? _sub;
  int _step = 0;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(WallpaperFillView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.shifts != widget.shifts) _listen();
  }

  void _listen() {
    _sub?.cancel();
    _sub = widget.shifts?.listen((_) => _shift());
  }

  void _shift() {
    if (!mounted || !widget.fill.animate || !widget.fill.canAnimate) return;
    if (MediaQuery.disableAnimationsOf(context)) return;
    // A burst of messages (catching up) makes one step.
    if (_move.isAnimating) return;
    _move.value = 0;
    _move.forward().whenComplete(() {
      if (!mounted || _move.value < 1) return;
      setState(() {
        _step = (_step + 1) % WallpaperGradient.ring.length;
        _move.value = 0;
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _move.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.fill.colors;
    final Widget fill;
    if (colors.length == 1) {
      fill = ColoredBox(color: colors.first);
    } else if (colors.length == 2) {
      fill = DecoratedBox(
          decoration: BoxDecoration(
              gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: colors)));
    } else {
      fill = CustomPaint(
        painter: _GradientPainter(colors, _step, _move),
        size: Size.infinite,
      );
    }
    final wash = widget.wash;
    return ClipRect(
      child: Stack(fit: StackFit.expand, children: [
        fill,
        if (wash != null) ColoredBox(color: wash),
      ]),
    );
  }
}

class _GradientPainter extends CustomPainter {
  _GradientPainter(this.colors, this.step, this.move) : super(repaint: move);

  final List<Color> colors;
  final int step;
  final Animation<double> move;

  /// Squares per side of the mesh; colors blend smoothly inside each.
  static const int cells = 16;

  @override
  void paint(Canvas canvas, Size size) {
    final phase = step + Curves.easeInOut.transform(move.value);
    final centers = WallpaperGradient.centers(colors.length, phase);
    const n = cells + 1;
    final positions = Float32List(n * n * 2);
    final vertexColors = Int32List(n * n);
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        final i = y * n + x;
        final point = Offset(x / cells, y / cells);
        positions[i * 2] = point.dx * size.width;
        positions[i * 2 + 1] = point.dy * size.height;
        vertexColors[i] =
            WallpaperGradient.colorAt(point, colors, centers).toARGB32();
      }
    }
    final indices = Uint16List(cells * cells * 6);
    var k = 0;
    for (var y = 0; y < cells; y++) {
      for (var x = 0; x < cells; x++) {
        final a = y * n + x;
        indices[k++] = a;
        indices[k++] = a + 1;
        indices[k++] = a + n;
        indices[k++] = a + 1;
        indices[k++] = a + n + 1;
        indices[k++] = a + n;
      }
    }
    final vertices = ui.Vertices.raw(ui.VertexMode.triangles, positions,
        colors: vertexColors, indices: indices);
    // Modulate with white keeps the vertex colors as they are.
    canvas.drawVertices(
        vertices, BlendMode.modulate, Paint()..color = Colors.white);
    vertices.dispose();
  }

  @override
  bool shouldRepaint(_GradientPainter old) =>
      old.step != step || !listEquals(old.colors, colors);
}
