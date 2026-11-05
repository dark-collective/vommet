// Proof renders for the GitHub unit gate (see /root/vommet-tools/RENDERS.md).
// Copy to commet/unit_test/render/render_png.dart in the GATE tree only; a
// render test prints PNGs into the gate log, render-extract.sh decodes them.
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

bool _fontsLoaded = false;

/// Loads the app's real fonts (Roboto as the theme's RobotoCustom and as
/// Roboto, NunitoSans for headlines, the Material icons from the Flutter
/// SDK) so renders show real glyphs and widths instead of Ahem boxes.
/// Call it inside the test body (it needs the test binding).
Future<void> loadRenderFonts(WidgetTester tester) async {
  if (_fontsLoaded) return;
  _fontsLoaded = true;
  Future<void> family(String name, List<Future<ByteData>> data) async {
    final loader = FontLoader(name);
    for (final d in data) {
      loader.addFont(d);
    }
    await loader.load();
  }

  Future<ByteData> asset(String path) => rootBundle.load(path);
  Future<ByteData> file(String path) async =>
      ByteData.sublistView(await File(path).readAsBytes());

  await tester.runAsync(() async {
    const roboto = [
      'assets/font/roboto/Roboto-Regular.ttf',
      'assets/font/roboto/Roboto-Bold.ttf',
    ];
    for (final name in ['RobotoCustom', 'Roboto']) {
      try {
        await family(name, [for (final p in roboto) asset(p)]);
      } catch (e) {
        print('@@RENDER-NOTE font $name: $e');
      }
    }
    try {
      await family('NunitoSans', [
        asset(
            'assets/font/nunito/NunitoSans-VariableFont_YTLC,opsz,wdth,wght.ttf')
      ]);
    } catch (e) {
      print('@@RENDER-NOTE font NunitoSans: $e');
    }
    // The Material icons font ships with the Flutter SDK, not the app.
    final roots = <String>[
      if (Platform.environment['FLUTTER_ROOT'] != null)
        Platform.environment['FLUTTER_ROOT']!,
      // flutter_tester lives in <root>/bin/cache/artifacts/engine/<arch>/
      File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.path,
    ];
    for (final root in roots) {
      final f = File('$root/bin/cache/artifacts/material_fonts/'
          'MaterialIcons-Regular.otf');
      if (f.existsSync()) {
        await family('MaterialIcons', [file(f.path)]);
        return;
      }
    }
    print('@@RENDER-NOTE MaterialIcons not found (roots: $roots)');
  });
}

/// Prints the nearest RepaintBoundary at or above [finder] as a PNG into the
/// test output: `@@RENDER <name> <w>x<h>@@`, `@@D <name> <seq> <base64>`
/// lines, `@@END <name>@@`. Names: [a-zA-Z0-9_.-].
Future<void> emitRender(WidgetTester tester, Finder finder, String name,
    {double pixelRatio = 2}) async {
  RenderObject? ro = finder.evaluate().first.renderObject;
  while (ro != null && ro is! RenderRepaintBoundary) {
    ro = ro.parent;
  }
  if (ro is! RenderRepaintBoundary) {
    print('@@RENDER-NOTE $name: no RepaintBoundary at or above the finder');
    return;
  }
  final boundary = ro;
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  });
  final b64 = base64Encode(bytes!);
  final size = boundary.size;
  print('@@RENDER $name ${(size.width * pixelRatio).round()}x'
      '${(size.height * pixelRatio).round()}@@');
  const chunk = 900;
  for (var i = 0, seq = 0; i < b64.length; i += chunk, seq++) {
    final end = i + chunk < b64.length ? i + chunk : b64.length;
    print('@@D $name $seq ${b64.substring(i, end)}');
  }
  print('@@END $name@@');
}
