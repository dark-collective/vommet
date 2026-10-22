// Vommet: draw on or redact a picture before sending it (Vommet issue 383).
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crop_image/crop_image.dart';
import 'package:flutter/material.dart';

/// One edit on top of a picture. Coordinates are normalized to (0, 0) x
/// (1, 1) of the unrotated picture, so they survive rotating and cropping.
sealed class MarkupEdit {
  const MarkupEdit();
}

/// A freehand line. [width] is a fraction of the picture's shorter side, so
/// the line looks the same thickness on screen and in the sent picture.
class MarkupStroke extends MarkupEdit {
  MarkupStroke(this.color, this.width, [List<Offset>? points])
      : points = points ?? [];

  final Color color;
  final double width;
  final List<Offset> points;
}

/// How a redaction hides what is under it.
enum RedactionStyle { black, pixelate, blur }

/// A block that hides part of the picture. Flattening paints it opaque over
/// the picture, so the pixels underneath are gone from the sent file, not
/// hidden by a layer.
class MarkupRedaction extends MarkupEdit {
  MarkupRedaction(this.rect, {this.style = RedactionStyle.black});

  final Rect rect;
  final RedactionStyle style;

  /// For [RedactionStyle.pixelate] and [RedactionStyle.blur]: the scrambled
  /// pixels painted over [rect], at the source picture's resolution (see
  /// [ImageMarkup.ensurePatches]). Owned by the [ImageMarkup] holding this
  /// edit.
  ui.Image? patch;
}

class ImageMarkup extends ChangeNotifier {
  static const Color redactionColor = Color(0xFF000000);
  static const double penWidth = 0.008;

  static const List<Color> penColors = [
    Color(0xFFE53935),
    Color(0xFFFDD835),
    Color(0xFF43A047),
    Color(0xFF1E88E5),
    Color(0xFFFFFFFF),
    Color(0xFF000000),
  ];

  final List<MarkupEdit> edits = [];

  bool get isEmpty => edits.isEmpty;

  void add(MarkupEdit edit) {
    edits.add(edit);
    notifyListeners();
  }

  /// Replaces the last edit while it is being dragged out.
  void replaceLast(MarkupEdit edit) {
    _disposePatch(edits.last);
    edits[edits.length - 1] = edit;
    notifyListeners();
  }

  void addPoint(Offset point) {
    final last = edits.lastOrNull;
    if (last is! MarkupStroke) return;
    last.points.add(point);
    notifyListeners();
  }

  void undo() {
    if (edits.isEmpty) return;
    _disposePatch(edits.removeLast());
    notifyListeners();
  }

  void clear() {
    edits.forEach(_disposePatch);
    edits.clear();
    notifyListeners();
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    edits.forEach(_disposePatch);
    super.dispose();
  }

  static void _disposePatch(MarkupEdit edit) {
    if (edit is MarkupRedaction) {
      edit.patch?.dispose();
      edit.patch = null;
    }
  }

  ui.Image? _pixelsOf;
  ByteData? _pixels;

  /// Makes the patches of the pixelate and blur redactions in [edits] that
  /// don't have one yet, from [source], then repaints. The source's pixels
  /// are read once and kept while [source] stays the same.
  Future<void> preparePatches(ui.Image source) async {
    if (!identical(_pixelsOf, source)) {
      _pixelsOf = source;
      _pixels = await source.toByteData(format: ui.ImageByteFormat.rawRgba);
    }
    if (_disposed) return;
    await ensurePatches(source, edits, pixels: _pixels);
    if (_disposed) {
      edits.forEach(_disposePatch);
      return;
    }
    notifyListeners();
  }

  static bool _needsPatch(MarkupEdit edit) =>
      edit is MarkupRedaction &&
      edit.style != RedactionStyle.black &&
      edit.patch == null &&
      !edit.rect.isEmpty;

  /// Gives every pixelate and blur redaction in [edits] a patch made from
  /// [source]. A patch is never made from the exact pixels under it: each
  /// block of at least 8x8 pixels is averaged, given random noise and
  /// coarsely quantized, on a randomly offset grid, and blur only smooths
  /// that mosaic. So the hidden content can't be recovered by un-blurring or
  /// by matching pixelated text against rendered fonts. [random] is for
  /// tests; it defaults to a secure generator.
  static Future<void> ensurePatches(ui.Image source, List<MarkupEdit> edits,
      {ByteData? pixels, math.Random? random}) async {
    final todo = edits.where(_needsPatch).cast<MarkupRedaction>().toList();
    if (todo.isEmpty) return;
    pixels ??= await source.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (pixels == null) return;
    final rgba = pixels.buffer.asUint8List();
    final rng = random ?? math.Random.secure();
    final size = Size(source.width.toDouble(), source.height.toDouble());
    for (final edit in todo) {
      final r = pixelRect(edit.rect, size);
      final left = r.left.toInt(), top = r.top.toInt();
      final w = r.width.toInt(), h = r.height.toInt();
      if (w <= 0 || h <= 0) continue;
      final out =
          scramble(rgba, source.width, left, top, w, h, edit.style, rng);
      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
          out, w, h, ui.PixelFormat.rgba8888, completer.complete);
      final patch = await completer.future;
      // Undone, or made by someone else, while this one was being made.
      if (edit.patch != null || !edits.contains(edit)) {
        patch.dispose();
      } else {
        edit.patch = patch;
      }
    }
  }

  /// The block size [scramble] uses for a [w] x [h] area.
  static int blockSize(int w, int h) => math.max(8, math.min(w, h) ~/ 4);

  /// Returns [w] x [h] RGBA pixels that hide the area at ([left], [top]) of
  /// the [width]-wide RGBA picture [rgba]: a noisy, quantized mosaic of it,
  /// blurred for [RedactionStyle.blur]. Every pixel is opaque.
  static Uint8List scramble(Uint8List rgba, int width, int left, int top, int w,
      int h, RedactionStyle style, math.Random rng) {
    final b = blockSize(w, h);
    final ox = rng.nextInt(b), oy = rng.nextInt(b);
    final cols = (w + ox + b - 1) ~/ b, rows = (h + oy + b - 1) ~/ b;
    final sums = Float64List(cols * rows * 3);
    final counts = Int32List(cols * rows);
    for (var y = 0; y < h; y++) {
      final row = (y + oy) ~/ b;
      for (var x = 0; x < w; x++) {
        final block = row * cols + (x + ox) ~/ b;
        final i = ((top + y) * width + left + x) * 4;
        sums[block * 3] += rgba[i];
        sums[block * 3 + 1] += rgba[i + 1];
        sums[block * 3 + 2] += rgba[i + 2];
        counts[block]++;
      }
    }
    // Block colour = mean + noise of up to +-32, quantized to 16 levels.
    final colors = Uint8List(cols * rows * 3);
    for (var block = 0; block < counts.length; block++) {
      final n = math.max(1, counts[block]);
      for (var c = 0; c < 3; c++) {
        final v = sums[block * 3 + c] / n + rng.nextInt(65) - 32;
        colors[block * 3 + c] = (v.clamp(0, 255) ~/ 16) * 16 + 8;
      }
    }
    final out = Uint8List(w * h * 4);
    for (var y = 0; y < h; y++) {
      final row = (y + oy) ~/ b;
      for (var x = 0; x < w; x++) {
        final block = row * cols + (x + ox) ~/ b;
        final o = (y * w + x) * 4;
        out[o] = colors[block * 3];
        out[o + 1] = colors[block * 3 + 1];
        out[o + 2] = colors[block * 3 + 2];
        out[o + 3] = 255;
      }
    }
    if (style == RedactionStyle.blur) {
      // Three box blurs each way come close to a gaussian.
      for (var pass = 0; pass < 3; pass++) {
        _boxBlur(out, w, h, b, horizontal: true);
        _boxBlur(out, w, h, b, horizontal: false);
      }
    }
    return out;
  }

  /// A box blur of radius [r] along rows or columns, in place, with the
  /// edge pixels repeated past the edges.
  static void _boxBlur(Uint8List px, int w, int h, int r,
      {required bool horizontal}) {
    final len = horizontal ? w : h, lines = horizontal ? h : w;
    final step = horizontal ? 4 : w * 4;
    final line = Int32List(len * 3);
    final window = 2 * r + 1;
    for (var l = 0; l < lines; l++) {
      final start = horizontal ? l * w * 4 : l * 4;
      for (var i = 0; i < len; i++) {
        for (var c = 0; c < 3; c++) {
          line[i * 3 + c] = px[start + i * step + c];
        }
      }
      for (var c = 0; c < 3; c++) {
        var sum = 0;
        for (var k = -r; k <= r; k++) {
          sum += line[k.clamp(0, len - 1) * 3 + c];
        }
        for (var i = 0; i < len; i++) {
          px[start + i * step + c] = sum ~/ window;
          sum += line[math.min(i + r + 1, len - 1) * 3 + c] -
              line[math.max(i - r, 0) * 3 + c];
        }
      }
    }
  }

  /// [rect] (normalized) in pixels of a picture of [size], snapped outwards
  /// to whole pixels.
  static Rect pixelRect(Rect rect, Size size) => Rect.fromLTRB(
        (rect.left * size.width).floorToDouble(),
        (rect.top * size.height).floorToDouble(),
        (rect.right * size.width).ceilToDouble(),
        (rect.bottom * size.height).ceilToDouble(),
      );

  /// Paints [edits] over a picture drawn at `Offset.zero` with [size]. In a
  /// [preview], a pixelate or blur redaction still waiting for its patch is
  /// a see-through box; in the sent picture it is black, so nothing is ever
  /// left uncovered.
  static void paintEdits(Canvas canvas, Size size, List<MarkupEdit> edits,
      {bool preview = false}) {
    final shortSide = math.min(size.width, size.height);
    for (final edit in edits) {
      switch (edit) {
        case MarkupRedaction(:final rect, :final style, :final patch):
          // Snapped outwards to whole pixels and not antialiased, so no
          // edge pixel keeps a blend of what was there.
          final r = pixelRect(rect, size);
          final paint = Paint()
            ..blendMode = BlendMode.src
            ..isAntiAlias = false;
          if (style != RedactionStyle.black && patch != null) {
            canvas.drawImageRect(
                patch,
                Rect.fromLTWH(
                    0, 0, patch.width.toDouble(), patch.height.toDouble()),
                r,
                paint
                  ..filterQuality = style == RedactionStyle.pixelate
                      ? FilterQuality.none
                      : FilterQuality.low);
          } else if (style != RedactionStyle.black && preview) {
            canvas.drawRect(r, Paint()..color = const Color(0x66FFFFFF));
          } else {
            canvas.drawRect(r, paint..color = redactionColor);
          }
        case MarkupStroke(:final points, :final color, :final width):
          if (points.isEmpty) continue;
          final paint = Paint()
            ..color = color
            ..strokeWidth = math.max(1, width * shortSide)
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..style = PaintingStyle.stroke;
          final scaled =
              points.map((p) => Offset(p.dx * size.width, p.dy * size.height));
          if (points.length == 1) {
            canvas.drawPoints(ui.PointMode.points, scaled.toList(), paint);
            continue;
          }
          final path = Path()..moveTo(scaled.first.dx, scaled.first.dy);
          for (final p in scaled.skip(1)) {
            path.lineTo(p.dx, p.dy);
          }
          canvas.drawPath(path, paint);
      }
    }
  }

  /// Returns a new picture with [edits] painted into its pixels, at full
  /// resolution. The caller owns (and disposes) the result.
  static Future<ui.Image> flatten(ui.Image image, List<MarkupEdit> edits) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final size = Size(image.width.toDouble(), image.height.toDouble());
    canvas.drawImage(image, Offset.zero, Paint());
    paintEdits(canvas, size, edits);
    final picture = recorder.endRecording();
    final result = picture.toImage(image.width, image.height);
    return result.whenComplete(picture.dispose);
  }

  /// Maps a point on the rotated picture (normalized) back to the unrotated
  /// picture (normalized), where edits are stored.
  static Offset unrotate(Offset p, CropRotation rotation) {
    return switch (rotation) {
      CropRotation.up => p,
      CropRotation.right => Offset(p.dy, 1 - p.dx),
      CropRotation.down => Offset(1 - p.dx, 1 - p.dy),
      CropRotation.left => Offset(1 - p.dy, p.dx),
    };
  }
}

/// Draws the edits over a picture shown rotated in a box of the size it is
/// painted at; used in the editor and over the crop view. The rotation is
/// read from [controller] when painting, so rotating repaints the edits
/// without rebuilding the crop view.
class ImageMarkupPainter extends CustomPainter {
  ImageMarkupPainter(this.markup, this.controller, {this.image})
      : super(repaint: Listenable.merge([markup, controller]));

  final ImageMarkup markup;
  final CropController controller;

  /// Also paint the picture itself under the edits.
  final ui.Image? image;

  @override
  void paint(Canvas canvas, Size size) {
    final rotation = controller.rotation;
    final sideways = rotation.isSideways;
    final unrotated = sideways
        ? Size(size.height, size.width)
        : Size(size.width, size.height);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(rotation.radians);
    canvas.translate(-unrotated.width / 2, -unrotated.height / 2);
    final image = this.image;
    if (image != null) {
      paintImage(
          canvas: canvas,
          rect: Offset.zero & unrotated,
          image: image,
          fit: BoxFit.fill,
          filterQuality: FilterQuality.medium);
    }
    ImageMarkup.paintEdits(canvas, unrotated, markup.edits, preview: true);
    canvas.restore();
  }

  @override
  bool shouldRepaint(ImageMarkupPainter oldDelegate) =>
      oldDelegate.markup != markup ||
      oldDelegate.controller != controller ||
      oldDelegate.image != image;
}
