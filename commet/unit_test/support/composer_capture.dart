// Optional captures of the real widgets exercised by CI.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'composer_workshop_fixture.dart' as fixture;

const lines = 'Here is the plan for movie night this weekend.\n\n'
    'Let’s meet in voice around seven and choose a movie together.\n'
    'I’ll bring a few suggestions. Feel free to add yours!\n\n'
    'If you’re joining late, just drop a message here.';
Future<void> fonts(WidgetTester t) async {
  if (Platform.environment['PREVIEW_ICON_FONT'] == null) return;
  await t.runAsync(() async {
    Future<void> load(String name, String path) => (FontLoader(name)
          ..addFont(
              Future.value(ByteData.sublistView(File(path).readAsBytesSync()))))
        .load();
    await load('RobotoCustom', 'assets/font/roboto/Roboto-Regular.ttf');
    await load('Roboto', 'assets/font/roboto/Roboto-Regular.ttf');
    await load('NunitoSans',
        'assets/font/nunito/NunitoSans-VariableFont_YTLC,opsz,wdth,wght.ttf');
    await load('EmojiFont', 'assets/font/emoji-font/TwemojiCOLR.otf');
    await load('MaterialIcons', Platform.environment['PREVIEW_ICON_FONT']!);
  });
}

Future<void> capture(WidgetTester t, String name,
    {Key surface = fixture.comparisonSurface}) async {
  final output = Platform.environment['PREVIEW_OUTPUT'];
  if (output == null) return;
  await t
      .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
  await t.pump();
  final boundary = t.renderObject<RenderRepaintBoundary>(find.byKey(surface));
  await t.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1.5);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$output/$name.png')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
  });
  expect(t.takeException(), isNull);
}
