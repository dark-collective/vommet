import 'dart:convert';

import 'package:commet/config/composer_workshop.dart';
import 'package:commet/config/layout_style.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/random_emoji_button.dart';
import 'package:commet/ui/atoms/room_header.dart';
import 'package:commet/ui/organisms/chat/chat.dart';
import 'package:commet/ui/organisms/room_quick_access_menu/room_quick_access_menu.dart';
import 'package:commet/ui/pages/main/room_primary_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart' as mx;
import 'package:tiamat/atoms/tile.dart';
import 'package:tiamat/config/style/theme_amoled.dart';
import 'package:tiamat/config/style/theme_dark.dart';
import 'package:tiamat/config/style/theme_light.dart';

import 'roomlist_fixture.dart' as server;
import 'support/composer_capture.dart' as render;
import 'support/composer_workshop_fixture.dart' as fixture;
import 'support/room_page_fixtures.dart';

void main() {
  setUp(() async {
    server.stubResponse = (request) {
      final path = request.url.path;
      Object? body;
      if (path.endsWith('/messages'))
        body = {'chunk': [], 'state': [], 'start': 'p'};
      if (path.contains('/state/m.room.member/'))
        body = {'membership': 'join', 'displayname': 'Bob'};
      if (path.contains('/profile/')) body = {'displayname': 'Bob'};
      return body == null
          ? null
          : http.Response(jsonEncode(body), 200,
              headers: {'content-type': 'application/json'});
    };
    await fixture.alignmentSetUp();
    await preferences.experimentComposerWorkshop.set(true);
    await server.sync(roomPageClient, join: {
      callRoom: mx.JoinedRoomUpdate(state: [
        server.stateEvent('m.room.name', {'name': 'Vommet'}),
        server.stateEvent(
            'm.room.topic', {'topic': 'Matrix client and community updates'})
      ])
    });
  });
  tearDown(() async {
    await fixture.alignmentTearDown();
    server.stubResponse = null;
  });
  for (final (themeName, theme) in [
    ('dark', ThemeDark.theme),
    ('light', ThemeLight.theme),
    ('amoled', ThemeAmoled.theme)
  ]) {
    for (final style in LayoutStyle.values) {
      testWidgets('$themeName ${style.name}: mobile composer', (t) async {
        addTearDown(t.view.reset);
        await render.fonts(t);
        await pickLayoutStyle(style);
        await preferences.layoutOverride.set('mobile');
        t.view.physicalSize = const Size(390, 844);
        t.view.devicePixelRatio = 1;
        t.view.viewInsets = const FakeViewPadding(bottom: 280);
        await t.pumpWidget(MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: theme,
            home: RepaintBoundary(
                key: fixture.comparisonSurface,
                child: ComposerWorkshopScope(
                    child: Scaffold(
                        resizeToAvoidBottomInset: false,
                        body: Column(children: [
                          const SizedBox(
                              height: 28,
                              child: Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 20),
                                  child: Row(children: [
                                    Text('9:41',
                                        style: TextStyle(fontSize: 12)),
                                    Spacer(),
                                    Icon(Icons.signal_cellular_alt, size: 14),
                                    SizedBox(width: 6),
                                    Icon(Icons.wifi, size: 14),
                                    SizedBox(width: 6),
                                    Icon(Icons.battery_full, size: 16)
                                  ]))),
                          Tile.low(
                              caulkBorderBottom: true,
                              child: SizedBox(
                                  height: 50,
                                  child: Builder(
                                      builder: (context) => RoomHeader(
                                          roomFor(RoomCase.messages),
                                          onBurgerMenuTap: () {},
                                          menu: phoneRoomHeaderMenu(
                                              context,
                                              roomFor(RoomCase.messages),
                                              IconButton(
                                                  icon: const Icon(
                                                      Icons.chevron_right),
                                                  onPressed: () {})))))),
                          Expanded(
                              child: Stack(children: [
                            Positioned.fill(
                                child: RoomPrimaryView(
                                    roomFor(RoomCase.messages))),
                            const Positioned(
                                left: 0,
                                right: 0,
                                bottom: 0,
                                height: 280,
                                child: PreviewKeyboard())
                          ])),
                        ]))))));
        await settle(t);
        final field = find.descendant(
            of: find.byType(Chat), matching: find.byType(TextField));
        final composerBox = find.descendant(
            of: find.byType(Chat),
            matching: find.byKey(const ValueKey('composer-input')));
        await preferences.experimentComposerWorkshop.set(false);
        await settle(t);
        await render.capture(t, '$themeName-${style.name}-before-mobile');
        await preferences.experimentComposerWorkshop.set(true);
        await settle(t);
        double? bottomGap;
        for (final (name, draft) in [
          ('empty', ''),
          (
            'growing',
            'Here is the plan for movie night.\n\nLet’s meet in voice around seven.\nWho would like to join?'
          ),
          ('limit', List.filled(5, render.lines).join('\n\n'))
        ]) {
          await t.enterText(field, draft);
          await settle(t);
          final box = t.getRect(composerBox);
          final plus = t.getRect(find.byKey(const ValueKey('composer-attach')));
          final action = t.getRect(find.byKey(
              ValueKey(name == 'empty' ? 'composer-voice' : 'composer-send')));
          final emoji = t.getRect(find.byType(RandomEmojiButton));
          expect(plus.center.dy, closeTo(action.center.dy, .1));
          expect(emoji.center.dy, closeTo(action.center.dy, .1));
          expect(box.bottom, closeTo(564, .1));
          expect(box.left, closeTo(0, .1));
          expect(box.right, closeTo(390, .1));
          bottomGap ??= box.bottom - plus.center.dy;
          expect(box.bottom - plus.center.dy, closeTo(bottomGap, .1));
          if (name == 'empty') {
            expect(box.height, 52);
            final editable = t
                .state<EditableTextState>(find.byType(EditableText))
                .renderEditable;
            expect(
                editable
                    .localToGlobal(editable
                        .getLocalRectForCaret(const TextPosition(offset: 0))
                        .center)
                    .dy,
                closeTo(plus.center.dy, 1));
            expect(find.byKey(const ValueKey('composer-popout')), findsNothing);
          } else {
            expect(
                find.byKey(const ValueKey('composer-popout')), findsOneWidget);
            final pop =
                t.getRect(find.byKey(const ValueKey('composer-popout')));
            expect(pop.overlaps(action), isFalse);
            expect(pop.overlaps(emoji), isFalse);
          }
          if (name == 'limit') {
            final textField = t.widget<TextField>(field);
            expect(textField.scrollController!.position.maxScrollExtent,
                greaterThan(0));
            // Inspect the draft from its beginning for the design capture.
            textField.scrollController!.jumpTo(0);
            await settle(t);
          }
          await render.capture(t, '$themeName-mobile-${style.name}-$name');
        }
        final before = t.getRect(composerBox);
        await t.tap(find.byKey(const ValueKey('composer-popout')));
        await settle(t);
        final after = t.getRect(composerBox);
        expect(after.height, greaterThan(before.height));
        expect(after.bottom, closeTo(564, .1));
        t.widget<TextField>(field).scrollController!.jumpTo(0);
        await settle(t);
        await render.capture(t, '$themeName-mobile-${style.name}-fullscreen');
        await t.tap(find.byKey(const ValueKey('composer-popout')));
        await settle(t);
        expect(t.getRect(composerBox).height, closeTo(before.height, .1));
        final input = t.widget<TextField>(field);
        expect(
            input.controller!.text, List.filled(5, render.lines).join('\n\n'));
        await finishRoomPage(t);
      }, variant: const TargetPlatformVariant({TargetPlatform.android}));
    }
  }
}

// Keyboard artwork supplies context only. Actual test viewInsets reserve its space.
class PreviewKeyboard extends StatelessWidget {
  const PreviewKeyboard({super.key});
  @override
  Widget build(BuildContext context) => ColoredBox(
      color: const Color(0xff25282c),
      child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
          child: Column(children: [
            const SizedBox(
                height: 30,
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [Text('I'), Text('the'), Text('you')])),
            for (final row in ['qwertyuiop', 'asdfghjkl', '^zxcvbnm<'])
              Expanded(
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                    for (final letter in row.split(''))
                      Expanded(
                          child: Padding(
                              padding: const EdgeInsets.all(3),
                              child: Container(
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                      color: const Color(0xff3c4046),
                                      borderRadius: BorderRadius.circular(5)),
                                  child: letter == '^'
                                      ? const Icon(Icons.arrow_upward, size: 20)
                                      : letter == '<'
                                          ? const Icon(Icons.backspace_outlined,
                                              size: 20)
                                          : Text(letter,
                                              style: const TextStyle(
                                                  fontSize: 18)))))
                  ])),
            Expanded(
                child: Row(children: [
              for (final (label, flex) in [
                ('?123', 2),
                (',', 1),
                ('English', 5),
                ('.', 1),
                ('↵', 2)
              ])
                Expanded(
                    flex: flex,
                    child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: Container(
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                                color: const Color(0xff3c4046),
                                borderRadius: BorderRadius.circular(5)),
                            child: label == '↵'
                                ? const Icon(Icons.keyboard_return, size: 20)
                                : Text(label))))
            ])),
            const SizedBox(
                height: 16,
                child: Center(
                    child: SizedBox(
                        width: 105,
                        height: 4,
                        child: ColoredBox(color: Color(0xffb8bbc1)))))
          ])));
}
