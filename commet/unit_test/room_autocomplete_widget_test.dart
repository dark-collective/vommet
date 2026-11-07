// Vommet issue 1223: real composer suggestions, selection and ordinary room links.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:commet/config/layout_style.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/molecules/message_input.dart';
import 'package:commet/utils/autofill_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/src/utils/markdown.dart' as mx_markdown;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_dark.dart';

import 'helpers/room_autocomplete_fixtures.dart';

void main() {
  setUp(() async {
    // unit_test/ is outside the analyzer's recognized test directory.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });
  tearDown(() async {
    await preferences.layoutOverride.set(null);
    await pickLayoutStyle(LayoutStyle.discord);
  });

  for (final style in LayoutStyle.values) {
    for (final width in [360.0, 1200.0]) {
      for (final inSpace in [false, true]) {
        testWidgets(
            '${style.name} $width ${inSpace ? "space" : "DM"}: suggest and insert address',
            (tester) async {
          await pickLayoutStyle(
              style == LayoutStyle.custom ? LayoutStyle.telegram : style);
          await pickLayoutStyle(style);
          await preferences.layoutOverride
              .set(width < 600 ? 'mobile' : 'desktop');
          tester.view.physicalSize = Size(width, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          tester.platformDispatcher.textScaleFactorTestValue = 1;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          if (Platform.environment['VOMMET_1223_CAPTURE_DIR'] != null) {
            await tester.runAsync(() async {
              Future<void> load(String name, String path) => (FontLoader(name)
                    ..addFont(Future.value(
                        ByteData.sublistView(File(path).readAsBytesSync()))))
                  .load();
              for (final name in ['RobotoCustom', 'Roboto']) {
                await load(name, 'assets/font/roboto/Roboto-Regular.ttf');
              }
              final iconPath = Platform.environment['SPECIMEN_ICON_FONT'];
              if (iconPath != null) await load('MaterialIcons', iconPath);
            });
          }
          final setup = AutocompleteSetup();
          final room = inSpace ? setup.current : setup.dm;
          const boundaryKey = ValueKey('room-autocomplete-capture');
          await tester.pumpWidget(RepaintBoundary(
            key: boundaryKey,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeDark.theme,
              home: Scaffold(
                  body: Column(children: [
                Expanded(
                    child: Center(
                        child: Text(inSpace
                            ? 'General · Garden community'
                            : 'Alex · standalone DM'))),
                MessageInput(
                  client: setup.client,
                  room: room,
                  isDirectMessage: !inSpace,
                  insetChatField: true,
                  desktopPaneHeight: width < 600 ? null : 800,
                  size: width < 600 ? 40 : 35,
                  iconScale: width < 600 ? 0.6 : 0.5,
                  availibleEmoticons: const [],
                  processAutofill: (text) =>
                      AutofillUtils.search(text, setup.client, room: room),
                  onSendMessage: (text, {overrideClient}) =>
                      MessageInputSendResult.success,
                ),
              ])),
            ),
          ));
          final field = find.byType(TextField);
          await tester.enterText(field, '#garden');
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          final rendered =
              tester.state<MessageInputState>(find.byType(MessageInput));
          expect(Theme.of(rendered.context).platform, TargetPlatform.linux);
          expect(Theme.of(rendered.context).brightness, Brightness.dark);
          expect(MediaQuery.textScalerOf(rendered.context).scale(14), 14);
          expect(currentLayoutStyle, style);
          expect(rendered.desktopEditor, width >= 600);
          final directory = Platform.environment['VOMMET_1223_CAPTURE_DIR'];
          if (directory != null) {
            final boundary = tester
                .renderObject<RenderRepaintBoundary>(find.byKey(boundaryKey));
            await tester.runAsync(() async {
              final image = await boundary.toImage();
              final bytes =
                  await image.toByteData(format: ui.ImageByteFormat.png);
              final output = File(
                  '$directory/${style.name}-${width.toInt()}-${inSpace ? "space" : "dm"}.png');
              output.parent.createSync(recursive: true);
              output.writeAsBytesSync(bytes!.buffer.asUint8List());
              File(output.path.replaceAll('.png', '.json'))
                  .writeAsStringSync(jsonEncode({
                'query': '#garden',
                'inset_chat_field': true,
                'desktop_pane_height': width < 600 ? null : 800,
                'is_direct_message': !inSpace,
                'platform': 'linux',
                'theme': 'Dark',
                'width': width,
                'height': 800,
                'dpr': 1,
                'text_scale': 1,
                'layout': style.name,
                'context': inSpace ? 'space' : 'dm',
                'suggestions':
                    rendered.autoFillResults?.map((r) => r.slug).toList() ?? [],
              }));
              image.dispose();
            });
          }
          final card = find.byKey(const ValueKey('composer-autofill-card'));
          expect(card, findsOneWidget);
          if (inSpace) {
            // This row exists on the base too: prove selection replaces the ID.
            await tester.tap(find.text('Garden notes'));
            await tester.pump();
            final selected =
                tester.state<MessageInputState>(find.byType(MessageInput));
            expect(selected.controller.text, '#notes:example.org ');
            await tester.enterText(field, '#garden');
            await tester.pump();
            await tester.pump();
          }
          expect(find.text('Garden community'), findsOneWidget);
          expect(find.text('Garden'), findsOneWidget);
          if (inSpace) {
            expect(tester.getTopLeft(find.text('Garden notes')).dy,
                lessThan(tester.getTopLeft(find.text('Garden')).dy));
          }
          expect(tester.takeException(), isNull);
          // Tap a real suggestion, rather than assigning the controller's text.
          await tester.tap(find.text('Garden'));
          await tester.pump();
          final state =
              tester.state<MessageInputState>(find.byType(MessageInput));
          expect(state.controller.text, '#garden:example.org ');
          await tester.pump();
          expect(card, findsNothing);
          expect(
              mx_markdown.markdown(state.controller.text),
              contains(
                  '<a href="https://matrix.to/#/#garden:example.org">#garden:example.org</a>'));
          // The keyboard acceptance path inserts the same ordinary address.
          await tester.enterText(field, '#seasonal-announcements');
          await tester.pump();
          if (state.autoFillSelection == null) {
            await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          }
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          expect(state.controller.text, '#garden:example.org ');
          await tester.enterText(field, '#zzzzzzzzzzzzzzzzzzzz');
          await tester.pump();
          await tester.pump();
          expect(card, findsNothing);
          // Re-query after the account's loaded aliases disappear.
          for (final candidate in setup.client.rooms.cast<AutocompleteRoom>()) {
            setLoadedAliases(candidate.matrixRoom, null);
          }
          setLoadedAliases(setup.parent.matrixRoom, null);
          await tester.enterText(field, '#');
          await tester.pump();
          await tester.pump();
          expect(card, findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
      }
    }
  }
}
