// Vommet: a room's timeline closes once no view shows it (follow-up to
// missed messages after a server outage). The chat only ended its visit,
// so every visited room's SDK timeline, and its sliding sync room
// subscription, stayed alive for the rest of the run, and a long pause
// checked all of them for gaps.
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/main.dart';
import 'package:commet/telemetry/telemetry.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:shared_preferences/shared_preferences.dart';

import 'roomlist_fixture.dart';

int _n = 0;

matrix.JoinedRoomUpdate joined(String roomId) => matrix.JoinedRoomUpdate(
      state: roomState(roomId),
      timeline: matrix.TimelineUpdate(events: [
        matrix.MatrixEvent(
          type: matrix.EventTypes.Message,
          content: {"msgtype": "m.text", "body": "hello"},
          senderId: "@bob:example.com",
          eventId: "\$e${_n++}",
          originServerTs:
              DateTime.fromMillisecondsSinceEpoch(1700000100000 + _n),
        ),
      ], prevBatch: "p"),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late MatrixClient client;
  var n = 0;
  final rooms = [for (var i = 0; i < 11; i++) "!r$i:example.com"];

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    client = await signedInClient("timeline-holders-${n++}");
    await sync(client, join: {for (final r in rooms) r: joined(r)});
  });

  tearDown(() => client.getMatrixClient().dispose(closeDatabase: true));

  bool isOpen(String roomId) =>
      client.getMatrixClient().slidingSyncController.gaps.isOpen(roomId);

  test("opening and leaving 10 rooms leaves only the open one live", () async {
    final baseline = Telemetry.timelinesLive;
    final shown = client.getRoom(rooms.last) as MatrixRoom;
    final view = Object();
    await shown.getTimeline(holder: view);

    for (final id in rooms.take(10)) {
      final room = client.getRoom(id) as MatrixRoom;
      final chat = Object();
      final timeline = await room.getTimeline(holder: chat);
      expect(isOpen(id), isTrue);
      room.releaseTimeline(timeline, chat);
      await pumpEventQueue();
      expect(room.timeline, isNull, reason: "the room's timeline is closed");
      expect(isOpen(id), isFalse, reason: "its room subscription ended");
    }
    expect(Telemetry.timelinesLive, baseline + 1);
    expect(rooms.where(isOpen), [rooms.last],
        reason: "a long pause checks only the room on screen");

    // Opening again works and shows the stored events.
    final again = await client.getRoom(rooms.first)!.getTimeline(holder: view);
    expect(again.events, isNotEmpty);
    expect(isOpen(rooms.first), isTrue);
  });

  test("a timeline shown in two places stays open when one closes", () async {
    final room = client.getRoom(rooms.first) as MatrixRoom;
    final baseline = Telemetry.timelinesLive;
    final main = Object(), side = Object();
    final timeline = await room.getTimeline(holder: main);
    room.holdTimeline(timeline, side);

    room.releaseTimeline(timeline, main);

    await pumpEventQueue();
    expect(room.timeline, same(timeline));
    expect(isOpen(rooms.first), isTrue);
    expect(Telemetry.timelinesLive, baseline + 1);

    room.releaseTimeline(timeline, side);

    await pumpEventQueue();
    expect(room.timeline, isNull);
    expect(isOpen(rooms.first), isFalse);
    expect(Telemetry.timelinesLive, baseline);
  });

  test("a newer timeline closes the old one once nothing holds it", () async {
    final room = client.getRoom(rooms.first) as MatrixRoom;
    final baseline = Telemetry.timelinesLive;
    final chat = Object(), jump = Object();
    final first = await room.getTimeline(holder: chat);
    final second = await room.getTimeline(holder: jump);
    expect(room.timeline, same(second));
    expect(Telemetry.timelinesLive, baseline + 2,
        reason: "the first one is still shown");

    room.releaseTimeline(first, chat);

    await pumpEventQueue();
    expect(Telemetry.timelinesLive, baseline + 1);
    expect(room.timeline, same(second), reason: "the shown one stays");
    expect(isOpen(rooms.first), isTrue);
    room.releaseTimeline(second, jump);
    await pumpEventQueue();
    expect(Telemetry.timelinesLive, baseline);
  });

  test("overlapping loads share one timeline, which stays the room's",
      () async {
    final room = client.getRoom(rooms.first) as MatrixRoom;
    final baseline = Telemetry.timelinesLive;
    final chat = Object(), media = Object();
    final loadA = room.getTimeline(holder: chat);
    final loadB = room.getTimeline(holder: media);
    final a = await loadA, b = await loadB;
    await pumpEventQueue();
    expect(b, same(a), reason: "the chat and the Media tab show one timeline");
    expect(room.timeline, same(a));
    expect(Telemetry.timelinesLive, baseline + 1);

    room.releaseTimeline(b, media);
    await pumpEventQueue();
    expect(room.timeline, same(a), reason: "the chat still shows it");
    expect(isOpen(rooms.first), isTrue);
    room.releaseTimeline(a, chat);
    await pumpEventQueue();
    expect(Telemetry.timelinesLive, baseline);
    expect(isOpen(rooms.first), isFalse, reason: "nothing leaks");
  });

  test("the Media tab joins a chat opening at its last read message", () async {
    final room = client.getRoom(rooms.first) as MatrixRoom;
    final lastRead = room.matrixRoom.lastEvent!.eventId;
    final chat = Object(), media = Object();
    final loadChat = room.getTimeline(contextEventId: lastRead, holder: chat);
    final loadMedia = room.getTimeline(holder: media, followShown: true);
    final shown = await loadChat, tab = await loadMedia;
    expect(tab, same(shown));
    expect(room.timeline, same(shown));
    room.releaseTimeline(tab, media);
    await pumpEventQueue();
    expect(room.timeline, same(shown), reason: "the chat still shows it");
  });

  test("a chat at the latest messages does not join a jump's load", () async {
    final room = client.getRoom(rooms.first) as MatrixRoom;
    final hit = room.matrixRoom.lastEvent!.eventId;
    // Send a newer message, so the hit is an older event.
    await sync(client, join: {rooms.first: joined(rooms.first)});
    expect(room.matrixRoom.lastEvent!.eventId, isNot(hit));
    final jump = Object(), chat = Object();
    final loadJump = room.getTimeline(contextEventId: hit, holder: jump);
    final loadChat = room.getTimeline(holder: chat);
    final atHit = await loadJump, latest = await loadChat;
    expect(identical(latest, atHit), isFalse,
        reason: "the chat opens at the latest messages, not around the hit");
    expect(room.timeline, same(latest),
        reason: "the chat's load started last, so it is the room's");
    room.releaseTimeline(atHit, jump);
    room.releaseTimeline(latest, chat);
  });

  test("a chat does not join a load made without a holder", () async {
    final room = client.getRoom(rooms.first) as MatrixRoom;
    final baseline = Telemetry.timelinesLive;
    final chat = Object();
    final loadSearch = room.getTimeline();
    final loadChat = room.getTimeline(holder: chat);
    final searched = await loadSearch, shown = await loadChat;
    expect(identical(shown, searched), isFalse);
    room.releaseTimeline(shown, chat);
    await pumpEventQueue();
    expect(room.timeline, isNot(same(shown)),
        reason: "the chat's timeline is closed when it leaves");
    expect(Telemetry.timelinesLive, baseline + 1,
        reason: "only the search's timeline stays open");
  });

  test("closing a newer timeline keeps the shown older one the room's",
      () async {
    final room = client.getRoom(rooms.first) as MatrixRoom;
    final chat = Object(), jump = Object();
    final first = await room.getTimeline(holder: chat);
    final second = await room.getTimeline(holder: jump);
    expect(room.timeline, same(second));

    room.releaseTimeline(second, jump);
    await pumpEventQueue();
    expect(room.timeline, same(first),
        reason: "read receipts and edit-last go to what the chat shows");
    expect(isOpen(rooms.first), isTrue);
  });

  test("a timeline loaded without a holder is never closed here", () async {
    final room = client.getRoom(rooms.first) as MatrixRoom;
    final timeline = await room.getTimeline();
    final chat = Object();
    room.holdTimeline(timeline, chat);
    room.releaseTimeline(timeline, chat);
    await pumpEventQueue();
    expect(room.timeline, same(timeline),
        reason: "search and other callers keep using it");
    expect(isOpen(rooms.first), isTrue);
  });
}
