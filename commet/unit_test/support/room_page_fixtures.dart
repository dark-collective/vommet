// The room page (RoomPrimaryView) in each state it can be in, with fakes only
// at the client/SDK boundary, and a check that no part of the page is left
// blank.
import 'dart:async';
import 'dart:math';

import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/client/matrix/components/profile/matrix_profile_component.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/client/timeline.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/molecules/call_encryption_strip.dart';
import 'package:commet/ui/molecules/compact_call_strip.dart';
import 'package:commet/ui/molecules/message_input.dart';
import 'package:commet/ui/molecules/room_call_bar.dart';
import 'package:commet/ui/organisms/call_view/call.dart';
import 'package:commet/ui/organisms/call_view/voip_stream_view.dart';
import 'package:commet/ui/organisms/chat/chat.dart';
import 'package:commet/ui/organisms/voip_room_view/voip_room_view.dart';
import 'package:commet/ui/pages/main/room_primary_view.dart';
import 'package:commet/utils/animation/ripple.dart';
import 'package:commet/utils/emoji/unicode_emoji.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_dark.dart';

import '../roomlist_fixture.dart';
import 'fake_voip_session.dart';

const callRoom = "!dm:example.com";
const emptyRoom = "!empty:example.com";
const voiceRoom = "!voice:example.com";
const roomViewKey = ValueKey('room-page');

/// The rooms the page is checked in. [callInTextRoom] is [messages] with a
/// call; the call's state comes from a [CallCase].
enum RoomCase { empty, messages, loading, failed, voice, callInTextRoom }

late MatrixClient roomPageClient;
var _n = 0;

matrix.MatrixEvent _message(int i) => matrix.MatrixEvent(
      type: matrix.EventTypes.Message,
      content: {"msgtype": "m.text", "body": "message $i"},
      senderId: i.isEven ? remoteUser : me,
      eventId: "\$m$i",
      originServerTs:
          DateTime.fromMillisecondsSinceEpoch(1700000100000 + i * 1000),
    );

/// A signed-in client with a room of 40 messages ([callRoom]), an empty room
/// and a voice room.
Future<void> roomPageSetUp() async {
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  await preferences.init();
  await UnicodeEmojis.load();
  roomPageClient = await signedInClient("room-page-${_n++}");
  roomPageClient.self =
      MatrixProfile(roomPageClient, matrix.Profile(userId: me));
  clientManager = ClientManager();
  clientManager!.callManager.playSounds = false;
  await sync(roomPageClient, join: {
    callRoom: matrix.JoinedRoomUpdate(
      state: roomState(callRoom, name: "User QS"),
      timeline: matrix.TimelineUpdate(
          events: [for (var i = 0; i < 40; i++) _message(i)], prevBatch: "p"),
    ),
    emptyRoom: matrix.JoinedRoomUpdate(
        state: roomState(emptyRoom, name: "Empty"),
        timeline: matrix.TimelineUpdate(events: [], prevBatch: "p")),
    voiceRoom: matrix.JoinedRoomUpdate(state: [
      stateEvent("m.room.create", {
        "creator": me,
        "type": "org.matrix.msc3417.call",
      }),
      stateEvent("m.room.member", {"membership": "join"}, stateKey: me),
      stateEvent("m.room.name", {"name": "Voice"}),
    ]),
  });
}

Future<void> roomPageTearDown() async {
  for (final s in [...?clientManager?.callManager.currentSessions]) {
    if (s is FakeVoipSession) s.state = VoipState.ended;
  }
  clientManager?.callManager.currentSessions.clear();
  clientManager = null;
  await roomPageClient.getMatrixClient().dispose(closeDatabase: true);
}

/// A room whose timeline load never finishes ([fail] false) or throws.
class TimelineGateRoom extends MatrixRoom {
  TimelineGateRoom(MatrixClient client, String id, {required this.fail})
      : super(client, client.getMatrixClient().getRoomById(id)!,
            client.getMatrixClient());
  final bool fail;
  final loading = Completer<Timeline>();

  @override
  Timeline? get timeline => null;

  @override
  Future<Timeline> getTimeline(
      {String? contextEventId, Object? holder, bool followShown = false}) {
    if (fail) return Future.error(Exception("Timeline failed to load"));
    return loading.future;
  }
}

Room roomFor(RoomCase r) => switch (r) {
      RoomCase.empty => roomPageClient.getRoom(emptyRoom)!,
      RoomCase.messages ||
      RoomCase.callInTextRoom =>
        roomPageClient.getRoom(callRoom)!,
      RoomCase.loading =>
        TimelineGateRoom(roomPageClient, callRoom, fail: false),
      RoomCase.failed => TimelineGateRoom(roomPageClient, callRoom, fail: true),
      RoomCase.voice => roomPageClient.getRoom(voiceRoom)!,
    };

/// Starts a call in [room] in [c] state, as the call manager would hold it.
FakeVoipSession startCall(Room room, CallCase c) {
  final session = FakeVoipSession.of(roomPageClient, room.identifier, c,
      roomName: room.displayName);
  clientManager!.callManager.currentSessions.add(session);
  return session;
}

/// The room page for [room] in a [width] x [height] window (a 50 px room
/// header above it, as in the app). Rebuilds when a call starts or ends, as
/// MainPage does.
Future<void> pumpRoomPage(WidgetTester tester, Room room,
    {required double width, required double height}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: ThemeDark.theme,
    home: Scaffold(
      body: Column(children: [
        const SizedBox(height: 50),
        Expanded(
          child: RepaintBoundary(
            key: roomViewKey,
            child: StreamBuilder(
              stream: clientManager!.callManager.currentSessions.onListUpdated,
              builder: (context, _) => RoomPrimaryView(room),
            ),
          ),
        ),
      ]),
    ),
  ));
  await settle(tester);
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> finishRoomPage(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(minutes: 2));
}

/// No blank band: the chat (or the voice room view that replaces it)
/// reaches the bottom of the room page, the message input (where there is
/// one) sits within 80 px of it, and nothing overflowed or threw. Above the
/// chat, the call area (call view, slim strip, encryption strip or the call
/// bar of a room with no call) starts at the top of the page and ends where
/// the chat starts, and a call view draws something: a tile, or the ringing
/// avatar of a call going out.
void expectFillsPage(WidgetTester tester, {String reason = ""}) {
  final error = tester.takeException();
  expect(error == null || error is MissingPluginException, isTrue,
      reason: "$reason: $error");
  final page = tester.getRect(find.byKey(roomViewKey));
  final chat = find.byType(Chat);
  final main = chat.evaluate().isNotEmpty ? chat : find.byType(VoipRoomView);
  expect(main, findsOneWidget, reason: "$reason: no chat or room view");
  final rect = tester.getRect(main);
  expect(rect.bottom, moreOrLessEquals(page.bottom, epsilon: 2),
      reason: "$reason: the room view stops ${page.bottom - rect.bottom} px "
          "above the bottom of the page");
  final input = find.byType(MessageInput);
  if (input.evaluate().isNotEmpty) {
    expect(page.bottom - tester.getRect(input.first).bottom, lessThan(80),
        reason: "$reason: the message input is far from the bottom");
  }
  if (main == chat) {
    final above = [
      for (final t in [
        CallWidget,
        CompactCallStrip,
        CallEncryptionStrip,
        RoomCallBar
      ])
        for (final e in find.byType(t).evaluate())
          tester.getRect(find.byElementPredicate((x) => x == e)),
    ];
    final top = above.isEmpty ? page.top : above.map((r) => r.top).reduce(min);
    final bottom =
        above.isEmpty ? page.top : above.map((r) => r.bottom).reduce(max);
    expect(top, moreOrLessEquals(page.top, epsilon: 2),
        reason: "$reason: the call area starts ${top - page.top} px below "
            "the top of the page");
    expect(rect.top, moreOrLessEquals(bottom, epsilon: 2),
        reason: "$reason: ${rect.top - bottom} px between the call area and "
            "the chat");
  }
  final call = find.byType(CallWidget);
  if (call.evaluate().isNotEmpty) {
    Finder inCall(Type t) =>
        find.descendant(of: call, matching: find.byType(t));
    expect(
        inCall(VoipStreamView).evaluate().isNotEmpty ||
            inCall(RippleAnimation).evaluate().isNotEmpty,
        isTrue,
        reason: "$reason: the call view draws no tile");
  }
}
