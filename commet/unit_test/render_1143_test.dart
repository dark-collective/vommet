// Gate-only proof renders for the desktop composer (Vommet issue 1143).
import 'package:commet/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'render/render_png.dart';
import 'support/room_page_fixtures.dart';

const _draft = 'one\ntwo\nthree\nfour\nfive\nsix\nseven\neight';

void main() {
  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    await preferences.layoutOverride.set('desktop');
  });
  for (final (name, text) in const [
    ('empty', ''),
    ('oneline', 'Hello there'),
    ('long', _draft),
  ]) {
    testWidgets('render r1143-$name', (tester) async {
      await loadRenderFonts(tester);
      final room = roomFor(RoomCase.messages);
      await pumpRoomPage(tester, room, width: 1014, height: 520);
      if (text.isNotEmpty) {
        await tester.enterText(find.byType(TextField).last, text);
        await settle(tester);
      }
      tester.takeException();
      await emitRender(tester, find.byKey(roomViewKey), 'r1143-$name',
          pixelRatio: 1);
      tester.takeException();
      await finishRoomPage(tester);
    }, variant: const TargetPlatformVariant({TargetPlatform.linux}));
  }
}
