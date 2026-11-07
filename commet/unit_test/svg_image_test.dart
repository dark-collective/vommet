import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:commet/utils/image/svg_image.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List bytesOf(String text) => Uint8List.fromList(utf8.encode(text));

const circle = '<svg xmlns="http://www.w3.org/2000/svg" width="40" '
    'height="20" viewBox="0 0 40 20"><circle cx="10" cy="10" r="8" '
    'fill="#f00"/></svg>';

/// [levels] groups, each drawing the previous one [copies] times.
String useBomb(int levels, int copies) {
  final defs = StringBuffer('<g id="l0"><rect width="1" height="1"/></g>');
  for (var level = 1; level <= levels; level++) {
    defs.write('<g id="l$level">');
    for (var i = 0; i < copies; i++) {
      defs.write('<use href="#l${level - 1}"/>');
    }
    defs.write('</g>');
  }
  return '<svg xmlns="http://www.w3.org/2000/svg"><defs>$defs</defs>'
      '<use href="#l$levels"/></svg>';
}

void main() {
  group("looksLikeSvg", () {
    test("an svg root element", () {
      expect(SvgImage.looksLikeSvg(bytesOf(circle)), isTrue);
      expect(SvgImage.looksLikeSvg(bytesOf("<svg/>")), isTrue);
    });

    test("after a BOM, XML declaration, comment and doctype", () {
      final text = '﻿<?xml version="1.0" encoding="UTF-8"?>\n'
          '<!-- Created with Inkscape -->\n'
          '<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" '
          '"http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">\n$circle';
      expect(SvgImage.looksLikeSvg(bytesOf(text)), isTrue);
    });

    test("not other files", () {
      final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A]);
      expect(SvgImage.looksLikeSvg(png), isFalse);
      expect(SvgImage.looksLikeSvg(null), isFalse);
      expect(SvgImage.looksLikeSvg(Uint8List(0)), isFalse);
      expect(
          SvgImage.looksLikeSvg(bytesOf("<html><svg></svg></html>")), isFalse);
      expect(SvgImage.looksLikeSvg(bytesOf("<svgx></svgx>")), isFalse);
      expect(SvgImage.looksLikeSvg(bytesOf("<?xml version='1.0'")), isFalse);
    });
  });

  group("isSafe", () {
    test("an ordinary svg", () {
      expect(SvgImage.isSafe(bytesOf(circle)), isTrue);
      expect(SvgImage.isSafe(bytesOf(useBomb(3, 4))), isTrue);
    });

    test("not nested references that multiply into too many shapes", () {
      // 10^6 rectangles from about 60 elements.
      expect(SvgImage.isSafe(bytesOf(useBomb(6, 10))), isFalse);
    });

    test("not the same bomb through url(#id) references", () {
      final defs = StringBuffer('<g id="m0"><rect width="1"/></g>');
      for (var level = 1; level <= 6; level++) {
        defs.write('<mask id="m$level">');
        for (var i = 0; i < 10; i++) {
          defs.write('<rect mask="url(#m${level - 1})"/>');
        }
        defs.write('</mask>');
      }
      final svg = '<svg><defs>$defs</defs><rect mask="url(#m6)"/></svg>';
      expect(SvgImage.isSafe(bytesOf(svg)), isFalse);
    });

    test("not reference loops", () {
      expect(
          SvgImage.isSafe(
              bytesOf('<svg><g id="a"><use xlink:href="#a"/></g></svg>')),
          isFalse);
      expect(
          SvgImage.isSafe(bytesOf('<svg><g id="a"><use href="#b"/></g>'
              '<g id="b"><use href="#a"/></g></svg>')),
          isFalse);
    });

    test("not entities, other roots, broken XML or huge files", () {
      expect(
          SvgImage.isSafe(bytesOf('<!DOCTYPE svg [<!ENTITY a "aaaa">]>'
              '<svg><text>&a;</text></svg>')),
          isFalse);
      expect(SvgImage.isSafe(bytesOf("<html></html>")), isFalse);
      expect(SvgImage.isSafe(bytesOf("<svg><g></svg>")), isFalse);
      final huge = '<svg>${" " * SvgImage.maxBytes}</svg>';
      expect(SvgImage.isSafe(bytesOf(huge)), isFalse);
    });

    test("not too deep", () {
      final svg = '<svg>${"<g>" * 200}${"</g>" * 200}</svg>';
      expect(SvgImage.isSafe(bytesOf(svg)), isFalse);
    });
  });

  group("drawSize", () {
    test("keeps the aspect ratio at the asked height", () {
      expect(SvgImage.drawSize(40, 20, 256), (width: 512, height: 256));
    });

    test("fits both sides within maxSide", () {
      expect(SvgImage.drawSize(100, 10, 1024),
          (width: SvgImage.maxSide, height: 205));
      expect(SvgImage.drawSize(10, 10, 100000),
          (width: SvgImage.maxSide, height: SvgImage.maxSide));
    });

    test("a picture without a size is drawn square", () {
      expect(SvgImage.drawSize(0, 0, 64), (width: 64, height: 64));
      expect(SvgImage.drawSize(double.nan, 5, 64), (width: 64, height: 64));
    });
  });

  group("readSmallSvg", () {
    Stream<List<int>> chunks(Uint8List bytes, int size) async* {
      for (var i = 0; i < bytes.length; i += size) {
        yield bytes.sublist(
            i, i + size > bytes.length ? bytes.length : i + size);
      }
    }

    test("returns an svg", () async {
      final svg = bytesOf(circle);
      expect(await SvgImage.readSmallSvg(chunks(svg, 7)), svg);
    });

    test("stops early on a file that isn't an svg", () async {
      var pulled = 0;
      final controller = StreamController<List<int>>();
      controller.onListen = () async {
        for (var i = 0; i < 1000 && !controller.isClosed; i++) {
          pulled++;
          controller.add(Uint8List(1024));
          await Future<void>.delayed(Duration.zero);
        }
        await controller.close();
      };
      controller.onCancel = () => controller.close();

      expect(await SvgImage.readSmallSvg(controller.stream), isNull);
      expect(pulled, lessThan(10));
    });

    test("stops on an svg bigger than maxBytes", () async {
      final big = bytesOf('<svg>${" " * SvgImage.maxBytes}</svg>');
      expect(await SvgImage.readSmallSvg(chunks(big, 65536)), isNull);
    });
  });

  group("toPng", () {
    testWidgets("draws an svg at the asked height", (tester) async {
      final png = await tester
          .runAsync(() => SvgImage.toPng(bytesOf(circle), height: 64));
      expect(png, isNotNull);

      final size = await tester.runAsync(() async {
        final codec = await ui.instantiateImageCodec(png!);
        final frame = await codec.getNextFrame();
        return (width: frame.image.width, height: frame.image.height);
      });
      expect(size, (width: 128, height: 64));
    });

    testWidgets("ignores external images instead of fetching them",
        (tester) async {
      const svg = '<svg xmlns="http://www.w3.org/2000/svg" '
          'xmlns:xlink="http://www.w3.org/1999/xlink" width="10" height="10">'
          '<image href="https://example.org/track.png" width="10" height="10"/>'
          '<image xlink:href="file:///etc/passwd" width="10" height="10"/>'
          '</svg>';
      var connections = 0;
      final png = await tester.runAsync(() =>
          HttpOverrides.runZoned(() => SvgImage.toPng(bytesOf(svg), height: 10),
              createHttpClient: (_) {
            connections++;
            throw StateError("no network in an svg");
          }));
      expect(png, isNotNull);
      expect(connections, 0);
    });

    testWidgets("refuses an unsafe svg", (tester) async {
      final png = await tester
          .runAsync(() => SvgImage.toPng(bytesOf(useBomb(6, 10)), height: 10));
      expect(png, isNull);
    });
  });
}
