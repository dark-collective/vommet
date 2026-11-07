// Room page with a call open: the call above, the chat filling the rest.
// Report 2026-11-04 (Linux desktop, 1014x1060 window): in a 1:1 call with
// only the caller in it and nothing published, the call view had nothing to
// draw, the chat kept the top half and the bottom stayed black.
import 'package:commet/client/components/voip/voip_stream.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/molecules/compact_call_strip.dart';
import 'package:commet/ui/molecules/message_input.dart';
import 'package:commet/ui/organisms/call_view/call.dart';
import 'package:commet/ui/organisms/chat/chat.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'roomlist_fixture.dart';
import 'support/fake_voip_session.dart';
import 'support/room_page_fixtures.dart';

/// The call states to check: ringing out, connected with nothing published
/// (the report), alone with the microphone on, both in it.
enum CallLayoutCase { outgoing, empty, alone, both }

CallCase _shared(CallLayoutCase c) => switch (c) {
      CallLayoutCase.outgoing => CallCase.outgoing,
      CallLayoutCase.empty => CallCase.empty,
      CallLayoutCase.alone => CallCase.alone,
      CallLayoutCase.both => CallCase.remote,
    };

/// The room page in a [width] x [height] window with a call in [c] state,
/// or no call.
Future<void> pumpRoomCall(WidgetTester tester,
    {required double width, required double height, CallLayoutCase? c}) async {
  final room = roomPageClient.getRoom(callRoom)!;
  if (c != null) startCall(room, _shared(c));
  await pumpRoomPage(tester, room, width: width, height: height);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  setUp(roomPageSetUp);
  tearDown(roomPageTearDown);

  for (final (w, h) in [(1014.0, 1060.0), (1600.0, 1000.0), (400.0, 860.0)]) {
    for (final c in CallLayoutCase.values) {
      testWidgets(
          "${w.toInt()}x${h.toInt()} ${c.name}: the chat reaches "
          "the bottom of the room page", (tester) async {
        await pumpRoomCall(tester, width: w, height: h, c: c);
        final error = tester.takeException();
        expect(error == null || error is MissingPluginException, isTrue,
            reason: "$error");
        final page = tester.getRect(find.byKey(roomViewKey));
        final chat = tester.getRect(find.byType(Chat));
        final input = tester.getRect(find.byType(MessageInput).first);
        // ignore: avoid_print
        print("@@LAYOUT ${w.toInt()}x${h.toInt()} ${c.name} page=$page "
            "chat=$chat input=$input");
        expect(chat.bottom, moreOrLessEquals(page.bottom, epsilon: 2));
        expect(page.bottom - input.bottom, lessThan(80));
        // Nothing to draw: the slim strip (with hang up) instead of a call
        // view sized to nothing.
        final empty = c == CallLayoutCase.empty;
        expect(find.byType(CompactCallStrip),
            empty ? findsOneWidget : findsNothing);
        expect(find.byType(CallWidget), empty ? findsNothing : findsOneWidget);
        await finishRoomPage(tester);
      });
    }
  }

  testWidgets("1014x1060: the call view comes back once a stream is published",
      (tester) async {
    await pumpRoomCall(tester,
        width: 1014, height: 1060, c: CallLayoutCase.empty);
    expect(find.byType(CompactCallStrip), findsOneWidget);
    final session =
        clientManager!.callManager.currentSessions.single as FakeVoipSession;
    session.publish(FakeVoipStream(me, VoipStreamDirection.outgoing));
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(CompactCallStrip), findsNothing);
    expect(find.byType(CallWidget), findsOneWidget);
    final page = tester.getRect(find.byKey(roomViewKey));
    final chat = tester.getRect(find.byType(Chat));
    expect(chat.bottom, moreOrLessEquals(page.bottom, epsilon: 2));
    await finishRoomPage(tester);
  });

  testWidgets("phone layout, nothing published: strip, chat to the bottom",
      (tester) async {
    await preferences.layoutOverride.set("mobile");
    await pumpRoomCall(tester,
        width: 400, height: 860, c: CallLayoutCase.empty);
    expect(find.byType(CompactCallStrip), findsOneWidget);
    final page = tester.getRect(find.byKey(roomViewKey));
    final chat = tester.getRect(find.byType(Chat));
    expect(chat.bottom, moreOrLessEquals(page.bottom, epsilon: 2));
    await finishRoomPage(tester);
  });

  testWidgets("1014x1060: the chat keeps its state when a call starts and ends",
      (tester) async {
    await pumpRoomCall(tester, width: 1014, height: 1060);
    final before = tester.state(find.byType(Chat));
    // The call list changes and the page rebuilds (main_page listens to
    // currentSessions), as when you press call or the other side answers.
    await pumpRoomCall(tester,
        width: 1014, height: 1060, c: CallLayoutCase.empty);
    expect(find.byType(CompactCallStrip), findsOneWidget);
    expect(tester.state(find.byType(Chat)), same(before));
    clientManager!.callManager.currentSessions.clear();
    await pumpRoomCall(tester, width: 1014, height: 1060);
    expect(find.byType(CompactCallStrip), findsNothing);
    expect(tester.state(find.byType(Chat)), same(before));
    await finishRoomPage(tester);
  });
}
