import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_svg/flutter_svg.dart';
import 'package:xml/xml.dart';

/// Vommet: draws SVG pictures (avatars, room and space icons, emotes) as
/// PNGs, since Flutter's image codecs can't decode SVG and homeservers don't
/// thumbnail it (Vommet issue 309).
///
/// The SVG comes from other people, so it is bounded before it is drawn: at
/// most [maxBytes] of source, at most [maxNodes] elements once `<use>` and
/// `url(#id)` references are expanded (a few nested references could
/// otherwise multiply into millions of shapes), no reference loops, no DTD
/// entities, and the result is at most [maxSide] pixels a side. The renderer
/// (flutter_svg's compiler) never fetches anything: `<image>` is only drawn
/// from `data:` URIs and references only resolve to ids in the same file.
class SvgImage {
  static const maxBytes = 1024 * 1024;
  static const maxNodes = 20000;
  static const maxDepth = 128;
  static const maxSide = 2048;

  /// How much of the start of a file [looksLikeSvg] reads.
  static const sniffLength = 4096;

  /// Whether [bytes] start like an SVG document: an `<svg>` root element,
  /// optionally after an XML declaration, comments and a doctype.
  static bool looksLikeSvg(Uint8List? bytes) {
    if (bytes == null) return false;
    var head = latin1.decode(
        bytes.length > sniffLength ? bytes.sublist(0, sniffLength) : bytes);
    if (head.startsWith("ï»¿")) head = head.substring(3);

    var i = 0;
    while (true) {
      while (i < head.length && head.codeUnitAt(i) <= 0x20) {
        i++;
      }

      int end;
      if (head.startsWith("<?", i)) {
        end = head.indexOf("?>", i);
        if (end < 0) return false;
        i = end + 2;
      } else if (head.startsWith("<!--", i)) {
        end = head.indexOf("-->", i);
        if (end < 0) return false;
        i = end + 3;
      } else if (head.startsWith("<!DOCTYPE", i)) {
        end = head.indexOf(">", i);
        if (end < 0) return false;
        i = end + 1;
      } else {
        if (!head.startsWith("<svg", i) || head.length <= i + 4) return false;
        final next = head.codeUnitAt(i + 4);
        return next <= 0x20 || next == 0x3E || next == 0x2F; // space, > or /
      }
    }
  }

  /// Whether [bytes] are an SVG within the limits above.
  static bool isSafe(Uint8List bytes) {
    if (bytes.length > maxBytes) return false;

    final XmlDocument document;
    try {
      final text = utf8.decode(bytes);
      if (text.contains("<!ENTITY")) return false;
      document = XmlDocument.parse(text);
    } catch (_) {
      return false;
    }

    if (document.rootElement.localName != "svg") return false;

    final byId = <String, XmlElement>{};
    var count = 0;
    for (final element in document.descendantElements) {
      if (++count > maxNodes) return false;
      final id = element.getAttribute("id");
      if (id != null) byId.putIfAbsent(id, () => element);
    }

    try {
      _expandedSize(
          document.rootElement, byId, Map.identity(), Set.identity(), 0);
      return true;
    } on _TooComplex {
      return false;
    }
  }

  static final _urlReference = RegExp(r"""url\(\s*['"]?#([^)'"\s]+)""");

  /// The ids [element] draws by reference: `href`/`xlink:href="#id"` and
  /// `url(#id)` in attributes or a `<style>` element.
  static Iterable<String> _references(XmlElement element) sync* {
    for (final attribute in element.attributes) {
      final value = attribute.value;
      if (attribute.name.local == "href" && value.startsWith("#")) {
        yield value.substring(1);
      }
      for (final match in _urlReference.allMatches(value)) {
        yield match.group(1)!;
      }
    }

    if (element.localName == "style") {
      for (final match in _urlReference.allMatches(element.innerText)) {
        yield match.group(1)!;
      }
    }
  }

  /// Elements under [element], counting each reference as a copy of what it
  /// points to. Throws [_TooComplex] past the limits or on a loop.
  static int _expandedSize(XmlElement element, Map<String, XmlElement> byId,
      Map<XmlElement, int> sizes, Set<XmlElement> open, int depth) {
    final known = sizes[element];
    if (known != null) return known;
    if (depth > maxDepth || !open.add(element)) throw _TooComplex();

    var total = 1;
    for (final child in element.childElements) {
      total += _expandedSize(child, byId, sizes, open, depth + 1);
      if (total > maxNodes) throw _TooComplex();
    }

    for (final id in _references(element)) {
      final target = byId[id];
      if (target == null) continue;
      total += _expandedSize(target, byId, sizes, open, depth + 1);
      if (total > maxNodes) throw _TooComplex();
    }

    open.remove(element);
    sizes[element] = total;
    return total;
  }

  /// The size to draw a [width] x [height] picture at: [targetHeight] high,
  /// shrunk to fit [maxSide] on both sides, aspect ratio kept.
  static ({int width, int height}) drawSize(
      double width, double height, int targetHeight) {
    if (!(width > 0 && height > 0 && width.isFinite && height.isFinite)) {
      width = 1;
      height = 1;
    }

    var outHeight = targetHeight.clamp(1, maxSide).toDouble();
    var outWidth = width * outHeight / height;
    if (outWidth > maxSide) {
      outHeight = outHeight * maxSide / outWidth;
      outWidth = maxSide.toDouble();
    }

    return (
      width: max(1, outWidth.round()),
      height: max(1, outHeight.round()),
    );
  }

  /// [bytes] as a PNG [height] pixels high, or null if they aren't a safe SVG.
  static Future<Uint8List?> toPng(Uint8List bytes,
      {required int height}) async {
    if (!isSafe(bytes)) return null;

    final info = await vg
        .loadPicture(SvgBytesLoader(bytes), null)
        .timeout(const Duration(seconds: 10));

    try {
      final size = drawSize(info.size.width, info.size.height, height);
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      if (info.size.width > 0 && info.size.height > 0) {
        canvas.scale(
            size.width / info.size.width, size.height / info.size.height);
      }
      canvas.drawPicture(info.picture);

      final picture = recorder.endRecording();
      final image = await picture.toImage(size.width, size.height);
      picture.dispose();

      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return data?.buffer.asUint8List();
    } finally {
      info.picture.dispose();
    }
  }

  /// Reads [stream] while it can still be an SVG of at most [maxBytes]: stops
  /// and returns null as soon as it is too big or doesn't start like one, so
  /// a large photo isn't downloaded for nothing.
  static Future<Uint8List?> readSmallSvg(Stream<List<int>> stream) async {
    final builder = BytesBuilder(copy: false);
    var sniffed = false;

    await for (final chunk in stream) {
      builder.add(chunk);
      if (builder.length > maxBytes) return null;
      if (!sniffed && builder.length >= sniffLength) {
        if (!looksLikeSvg(builder.toBytes())) return null;
        sniffed = true;
      }
    }

    final bytes = builder.takeBytes();
    return looksLikeSvg(bytes) ? bytes : null;
  }
}

class _TooComplex implements Exception {}
