// Vommet issue 1137: the real composer and search, in three layout styles
// and explicitly narrow phone/desktop sizes, independent of MOBILE.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:commet/config/layout_style.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/molecules/message_input.dart';
import 'package:commet/utils/autofill_utils.dart';
import 'package:commet/utils/emoji/unicode_emoji.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_dark.dart';

import 'support/emoji_alias_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (Platform.environment['VOMMET_CAPTURE_DIR'] == null) return;
    for (final font in {
      'RobotoCustom': 'assets/font/roboto/Roboto-Regular.ttf',
      'NunitoSans':
          'assets/font/nunito/NunitoSans-VariableFont_YTLC,opsz,wdth,wght.ttf',
      'EmojiFont': 'assets/font/emoji-font/TwemojiCOLR.otf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
    }
  });
  const captureKey = ValueKey('emoji-alias-composer');
  late EmojiAliasClient client;
  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    client = EmojiAliasClient(await UnicodeEmojis.load());
  });
  tearDown(() async {
    await preferences.layoutOverride.set(null);
    await pickLayoutStyle(LayoutStyle.discord);
  });

  for (final mobile in [true, false]) {
    for (final style in LayoutStyle.values) {
      testWidgets(
          '${mobile ? 'phone' : 'desktop'} ${style.name}: alias inserts once',
          (tester) async {
        tester.view.physicalSize =
            mobile ? const Size(360, 720) : const Size(1096, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        tester.platformDispatcher.textScaleFactorTestValue = 1;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await preferences.layoutOverride.set(mobile ? 'mobile' : 'desktop');
        if (style == LayoutStyle.custom)
          await pickLayoutStyle(LayoutStyle.telegram);
        await pickLayoutStyle(style);
        await tester.pumpWidget(RepaintBoundary(
          key: captureKey,
          child: MaterialApp(
            theme: ThemeDark.theme,
            home: Scaffold(
              body: Column(children: [
                const Expanded(child: SizedBox()),
                MessageInput(
                  client: client,
                  availibleEmoticons: UnicodeEmojis.packs!,
                  processAutofill: (text) => AutofillUtils.search(text, client),
                  onSendMessage: (message, {overrideClient}) =>
                      MessageInputSendResult.success,
                ),
              ]),
            ),
          ),
        ));
        await tester.enterText(find.byType(TextField).first, ':thumbsup');
        await tester.pump();
        await tester.pump();
        final directory = Platform.environment['VOMMET_CAPTURE_DIR'];
        if (directory != null) {
          final boundary = tester
              .renderObject<RenderRepaintBoundary>(find.byKey(captureKey));
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            await Directory(directory).create(recursive: true);
            await File(
                    '$directory/${mobile ? 'phone' : 'desktop'}-${style.name}.png')
                .writeAsBytes(data!.buffer.asUint8List());
            image.dispose();
          });
        }
        final card = find.byKey(const ValueKey('composer-autofill-card'));
        expect(card, findsOneWidget);
        final row = find.descendant(of: card, matching: find.text('+1'));
        expect(row, findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(row);
        await tester.pump();
        await tester.pump();
        final text = tester
            .widget<TextField>(find.byType(TextField).first)
            .controller!
            .text;
        expect(text.trim(), stockEmoji('+1').slug);
        expect(
            find.byKey(const ValueKey('composer-autofill-card')), findsNothing);
      }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
    }
  }
}
