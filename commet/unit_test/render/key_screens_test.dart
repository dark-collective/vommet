// Gate-only key-screen renders for every cut (cut-renders.sh; never committed
// to a topic). The room page in its main states, desktop and phone, drawn with
// the committed fixtures of unit_test/support/room_page_fixtures.dart. Lives at
// commet/unit_test/render/key_screens_test.dart in the gate tree.
import 'package:commet/main.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_voip_session.dart';
import '../support/room_page_fixtures.dart';
import 'render_png.dart';

const layouts = [
  ("desktop", 1014.0, 1060.0, false),
  ("phone", 400.0, 860.0, true),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  setUp(() async {
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => ['wifi'],
    );
    m.setMockStreamHandler(
      const EventChannel('dev.fluttercommunity.plus/connectivity_status'),
      MockStreamHandler.inline(
        onListen: (args, sink) => sink.success(['wifi']),
      ),
    );
    await roomPageSetUp();
  });
  tearDown(roomPageTearDown);

  for (final (layout, w, h, phone) in layouts) {
    final screens = <(String, RoomCase, CallCase?)>[
      ("messages", RoomCase.messages, null),
      ("empty", RoomCase.empty, null),
      ("failed", RoomCase.failed, null),
      ("voice", RoomCase.voice, null),
      for (final c in [
        CallCase.outgoing,
        CallCase.empty,
        CallCase.alone,
        CallCase.remote,
        CallCase.screenShare,
      ])
        ("call-${c.name}", RoomCase.callInTextRoom, c),
    ];
    for (final (screen, r, c) in screens) {
      final name = 'key-$layout-$screen';
      testWidgets('render $name', (tester) async {
        await loadRenderFonts(tester);
        if (phone) await preferences.layoutOverride.set("mobile");
        final room = roomFor(r);
        if (c != null) startCall(room, c);
        await pumpRoomPage(tester, room, width: w, height: h);
        tester.takeException();
        await emitRender(tester, find.byKey(roomViewKey), name, pixelRatio: 1);
        tester.takeException();
        await finishRoomPage(tester);
        // Desktop screens on a desktop platform: on the default (Android) test
        // platform the desktop-only paths, like the 1143 composer, never run.
      },
          variant: phone
              ? const DefaultTestVariant()
              : TargetPlatformVariant.only(TargetPlatform.linux));
    }
  }
}
