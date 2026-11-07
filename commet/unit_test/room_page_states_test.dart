// The whole room page in every state it can be in: empty room, messages,
// timeline loading or failed, voice room, and a call in a text room ringing,
// connected with nothing published, alone, with someone, with a screen
// share, ended and failed. No state may leave part of the page blank (a
// desktop call with nothing published once left the bottom half empty).
import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/client/components/voip/voip_stream.dart';
import 'package:commet/client/matrix/components/voip_room/matrix_livekit_voip_session.dart'
    show CallListenOnlyException;
import 'package:commet/main.dart';
import 'package:commet/ui/molecules/compact_call_strip.dart';
import 'package:commet/ui/organisms/call_view/call.dart';
import 'package:commet/ui/organisms/voip_room_view/voip_room_view.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';

import 'roomlist_fixture.dart';
import 'support/fake_voip_session.dart';
import 'support/room_page_fixtures.dart';

/// Window sizes; the last is the phone layout.
const layouts = [
  ("1014x1060", 1014.0, 1060.0, false),
  ("1600x1000", 1600.0, 1000.0, false),
  ("400x860", 400.0, 860.0, false),
  ("phone 400x860", 400.0, 860.0, true),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  setUp(roomPageSetUp);
  tearDown(roomPageTearDown);

  for (final (name, w, h, phone) in layouts) {
    Future<void> open(WidgetTester tester) async {
      if (phone) await preferences.layoutOverride.set("mobile");
    }

    for (final r
        in RoomCase.values.where((r) => r != RoomCase.callInTextRoom)) {
      testWidgets("$name ${r.name} room: the page is filled", (tester) async {
        await open(tester);
        await pumpRoomPage(tester, roomFor(r), width: w, height: h);
        expectFillsPage(tester, reason: "$name ${r.name}");
        if (r == RoomCase.voice) {
          expect(find.byType(VoipRoomView), findsOneWidget);
        }
        expect(find.byType(CallWidget), findsNothing);
        await finishRoomPage(tester);
      });
    }

    for (final c in [
      CallCase.outgoing,
      CallCase.empty,
      CallCase.alone,
      CallCase.remote,
      CallCase.screenShare,
    ]) {
      testWidgets("$name call ${c.name}: the chat reaches the bottom",
          (tester) async {
        await open(tester);
        final room = roomFor(RoomCase.callInTextRoom);
        startCall(room, c);
        await pumpRoomPage(tester, room, width: w, height: h);
        expectFillsPage(tester, reason: "$name call ${c.name}");
        // Nothing to draw: the slim strip (with hang up) instead of a call
        // view sized to nothing.
        if (c == CallCase.empty) {
          expect(find.byType(CompactCallStrip), findsOneWidget);
          expect(find.byType(CallWidget), findsNothing);
        }
        // Something to draw: the call view (expectFillsPage checks it has a
        // tile). Ringing out: the call view with the ringing avatar on
        // desktop; on the phone layout, which shows the call view only for
        // streams, the strip.
        if (c == CallCase.alone ||
            c == CallCase.remote ||
            c == CallCase.screenShare ||
            (c == CallCase.outgoing && !phone)) {
          expect(find.byType(CallWidget), findsOneWidget);
          expect(find.byType(CompactCallStrip), findsNothing);
        }
        if (c == CallCase.outgoing && phone) {
          expect(find.byType(CompactCallStrip), findsOneWidget);
        }
        await finishRoomPage(tester);
      });
    }

    testWidgets("$name call empty, then a stream: the call view comes back",
        (tester) async {
      await open(tester);
      final room = roomFor(RoomCase.callInTextRoom);
      final session = startCall(room, CallCase.empty);
      await pumpRoomPage(tester, room, width: w, height: h);
      expect(find.byType(CompactCallStrip), findsOneWidget);
      session.publish(FakeVoipStream(me, VoipStreamDirection.outgoing));
      await settle(tester);
      expect(find.byType(CompactCallStrip), findsNothing);
      expect(find.byType(CallWidget), findsOneWidget);
      expectFillsPage(tester, reason: "$name published");
      await finishRoomPage(tester);
    });

    testWidgets("$name call ended: no stale call view, page filled",
        (tester) async {
      await open(tester);
      final room = roomFor(RoomCase.callInTextRoom);
      final session = startCall(room, CallCase.remote);
      await pumpRoomPage(tester, room, width: w, height: h);
      expect(find.byType(CallWidget), findsOneWidget);
      await session.hangUpCall();
      await settle(tester);
      expect(find.byType(CallWidget), findsNothing);
      expect(find.byType(CompactCallStrip), findsNothing);
      expectFillsPage(tester, reason: "$name ended");
      await finishRoomPage(tester);
    });

    testWidgets(
        "$name call failed: the strip stays, the chat reaches the bottom",
        (tester) async {
      await open(tester);
      final room = roomFor(RoomCase.callInTextRoom);
      final session = startCall(room, CallCase.failed);
      await pumpRoomPage(tester, room, width: w, height: h);
      expectFillsPage(tester, reason: "$name failed, before");
      await expectLater(session.setMicrophoneMute(false),
          throwsA(isA<CallListenOnlyException>()));
      await settle(tester);
      // The call stays connected with nothing published: the slim strip with
      // hang up, never a call view sized to nothing.
      expect(session.state, VoipState.connected);
      expect(clientManager!.callManager.currentSessions, [session]);
      expect(find.byType(CompactCallStrip), findsOneWidget);
      expect(find.byType(CallWidget), findsNothing);
      expectFillsPage(tester, reason: "$name failed, after");
      await finishRoomPage(tester);
    });
  }
}
