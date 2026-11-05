// Vommet: a room's timeline closes once no view shows it (follow-up to
// missed messages after a server outage). The chat only ended its visit,
// so every visited room's SDK timeline, and its sliding sync room
// subscription, stayed alive for the rest of the run, and a long pause
// checked all of them for gaps.
import 'dart:async';

import 'package:commet/client/matrix/components/photo_album_room/matrix_photo_album_room_component.dart';
import 'package:commet/client/matrix/components/widgets/capabilities/mx_capability_receive_event.dart';
import 'package:commet/client/matrix/components/widgets/matrix_widget_component.dart';
import 'package:commet/client/matrix/components/widgets/matrix_widget_message_handler.dart';
import 'package:commet/client/matrix/components/encrypted_search_index/matrix_encrypted_search_index_component.dart';
import 'package:commet/client/matrix/components/event_search/matrix_event_search_component.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/main.dart';
import 'package:commet/telemetry/telemetry.dart';
import 'package:commet/ui/organisms/in_chat_search/in_chat_search.dart';
import 'package:commet/ui/organisms/photo_albums/photo_album_view.dart';
import 'package:commet/ui/organisms/room_event_search/room_event_search_widget.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_dark.dart';

import 'roomlist_fixture.dart';

int _n = 0;

/// The widget host (an external boundary): only the room and client are
/// real.
class _Runner extends MatrixWidgetRunner {
  _Runner(this.client, this.room);

  @override
  final MatrixClient client;

  @override
  final MatrixRoom room;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

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

  tearDown(() {
    searchResponse = null;
    messagesResponse = null;
    return client.getMatrixClient().dispose(closeDatabase: true);
  });

  bool isOpen(String roomId) =>
      client.getMatrixClient().slidingSyncController.gaps.isOpen(roomId);

  // Vommet: the on-device index session reads no room timeline, so in-chat
  // search keeps it when its chat goes (InChatSearch.detachChat).
  test("the on-device index search session holds no timeline", () async {
    final room = client.getRoom(rooms.first) as MatrixRoom;
    final index =
        MatrixEncryptedSearchIndexComponent(client, startBackground: false);
    final session = MatrixIndexedRoomEventSearchSession(room, index);
    expect(session.holdsTimeline, isFalse);
    expect(room.timeline, isNull, reason: "it loads none");
    session.close();
  });

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

  // Vommet: search, the photo album and widgets loaded a timeline without a
  // holder, which was never closed.
  Future<void> searchAndClose(MatrixRoom room) async {
    final search = InChatSearch(room, debounce: Duration.zero);
    search.open();
    search.text.text = "hello";
    search.onTextChanged("hello");
    await pumpEventQueue();
    search.close();
    await pumpEventQueue();
  }

  test("closing search and leaving the chat closes the room's timeline",
      () async {
    final room = client.getRoom(rooms.first) as MatrixRoom;
    final baseline = Telemetry.timelinesLive;
    final chat = Object();
    final timeline = await room.getTimeline(holder: chat);

    await searchAndClose(room);
    room.releaseTimeline(timeline, chat);

    await pumpEventQueue();
    expect(room.timeline, isNull);
    expect(isOpen(rooms.first), isFalse);
    expect(Telemetry.timelinesLive, baseline);
  });

  test("closing search keeps the open chat's timeline", () async {
    final room = client.getRoom(rooms.first) as MatrixRoom;
    final baseline = Telemetry.timelinesLive;
    final chat = Object();
    final timeline = await room.getTimeline(holder: chat);

    await searchAndClose(room);

    expect(room.timeline, same(timeline));
    expect(isOpen(rooms.first), isTrue);
    expect(Telemetry.timelinesLive, baseline + 1);
  });

  // Vommet: search is one per room for the whole run; leaving the chat
  // without closing it kept the session, and so the room's timeline.
  testWidgets("leaving the chat with search open closes the room's timeline",
      (tester) async {
    final room = client.getRoom(rooms.first) as MatrixRoom;
    final baseline = Telemetry.timelinesLive;
    final chat = Object();
    final search = InChatSearch(room, debounce: Duration.zero);
    await tester.runAsync(() async {
      final timeline = await room.getTimeline(holder: chat);
      search.attachChat(); // what the chat's initState does
      search.open();
      search.text.text = "hello";
      search.onTextChanged("hello");
      await pumpEventQueue();
      // The chat goes (room switch); search stays open.
      search.detachChat(); // what the chat's dispose does
      room.releaseTimeline(timeline, chat);
    });
    await tester.pump();
    await tester.runAsync(pumpEventQueue);

    expect(search.isOpen, isTrue);
    expect(search.text.text, "hello");
    expect(search.query, "hello");
    expect(room.timeline, isNull);
    expect(isOpen(rooms.first), isFalse,
        reason: "the sliding-sync gap tracking for the room is closed");
    expect(Telemetry.timelinesLive, baseline);
  });

  testWidgets("closing the photo album closes the room's timeline",
      (tester) async {
    // Its whole history synced (no prev_batch), so the album doesn't page
    // back through the stub server.
    const id = "!album:example.com";
    final update = joined(id);
    await tester.runAsync(() => sync(client, join: {
          id: matrix.JoinedRoomUpdate(
              state: update.state,
              timeline: matrix.TimelineUpdate(events: update.timeline!.events))
        }));
    final room = client.getRoom(id) as MatrixRoom;
    final baseline = Telemetry.timelinesLive;
    final album = MatrixPhotoAlbumRoomComponent(client, room);

    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(home: PhotoAlbumView(album)));
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pump();
    expect(Telemetry.timelinesLive, baseline + 1, reason: "the album loaded");

    // The album polls for more a second after its first load.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => pumpEventQueue());
    expect(room.timeline, isNull);
    expect(isOpen(id), isFalse);
    expect(Telemetry.timelinesLive, baseline);
  });

  test("a widget reading a closed room's events leaves no timeline", () async {
    final room = client.getRoom(rooms.first) as MatrixRoom;
    final baseline = Telemetry.timelinesLive;
    final capability = MatrixCapabilityReceiveEvent(
        runner: _Runner(client, room), eventType: matrix.EventTypes.Message);

    final reply = await capability.handleRequest(MatrixWidgetMessage(
        requestId: "1",
        action: "org.matrix.msc2876.read_events",
        data: {"type": matrix.EventTypes.Message},
        api: "fromWidget",
        widgetId: "w"));
    capability.sub?.cancel();

    expect((reply.response!["events"] as List), isNotEmpty);
    await pumpEventQueue();
    expect(room.timeline, isNull);
    expect(isOpen(rooms.first), isFalse);
    expect(Telemetry.timelinesLive, baseline);
  });

  // Vommet: the server search's real session (unencrypted room): looking
  // further back after leaving the chat goes on from `next_batch`.
  Map<String, Object?> page(String roomId, String eventId, int ts,
          {String? next}) =>
      {
        "search_categories": {
          "room_events": {
            "count": 2,
            if (next != null) "next_batch": next,
            "results": [
              {
                "rank": 1,
                "result": {
                  "type": "m.room.message",
                  "content": {"msgtype": "m.text", "body": "hello"},
                  "event_id": eventId,
                  "sender": "@bob:example.com",
                  "room_id": roomId,
                  "origin_server_ts": ts
                }
              }
            ]
          }
        }
      };

  testWidgets(
      "after leaving the chat, more server matches go on from "
      "next_batch", (tester) async {
    final room = client.getRoom(rooms.first) as MatrixRoom;
    expect(room.isE2EE, isFalse, reason: "the server search session");
    final asked = <String?>[];
    searchResponse = (url) {
      final next = url.queryParameters["next_batch"];
      asked.add(next);
      return next == null
          ? page(rooms.first, r"$s1", 1700000200000, next: "tok1")
          : page(rooms.first, r"$s2", 1700000100000);
    };
    final baseline = Telemetry.timelinesLive;
    final search = InChatSearch(room, debounce: Duration.zero);
    await tester.runAsync(() async {
      search.attachChat();
      search.open();
      search.text.text = "hello";
      search.onTextChanged("hello");
      await pumpEventQueue();
      expect(search.results.map((e) => e.eventId), [r"$s1"]);
      search.detachChat();
      await pumpEventQueue();
      expect(room.timeline, isNull, reason: "the chat went");
      expect(Telemetry.timelinesLive, baseline);
      search.attachChat();
      search.loadMore();
      await pumpEventQueue();
    });
    expect(asked, [null, "tok1"]);
    expect(search.results.map((e) => e.eventId), [r"$s1", r"$s2"]);
    await tester.runAsync(() async {
      search.close();
      search.detachChat();
      await pumpEventQueue();
    });
  });

  // Vommet: closed while the resumed search's first page is on its way: the
  // session has no `next_batch` yet, so reopening goes on from the old one.
  testWidgets(
      "closing before a resumed server page answers keeps its next_batch",
      (tester) async {
    final room = client.getRoom(rooms.first) as MatrixRoom;
    final asked = <String?>[];
    Completer<void>? held;
    searchResponse = (url) async {
      final next = url.queryParameters["next_batch"];
      asked.add(next);
      if (next == "tok1") await held?.future;
      return next == null
          ? page(rooms.first, r"$s1", 1700000200000, next: "tok1")
          : page(rooms.first, r"$s2", 1700000100000);
    };
    final search = InChatSearch(room, debounce: Duration.zero);
    await tester.runAsync(() async {
      search.attachChat();
      search.open();
      search.text.text = "hello";
      search.onTextChanged("hello");
      await pumpEventQueue();
      expect(search.results.map((e) => e.eventId), [r"$s1"]);
      search.close();
      search.open();
      held = Completer();
      search.loadMore();
      for (var i = 0; i < 500 && !asked.contains("tok1"); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      search.close();
      held!.complete();
      await pumpEventQueue();
      expect(room.timeline, isNull, reason: "closing let it go");
      search.open();
      for (var i = 0; i < 500 && search.results.length < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    expect(asked, [null, "tok1", "tok1"]);
    expect(search.results.map((e) => e.eventId), [r"$s1", r"$s2"]);
    await tester.runAsync(() async {
      search.close();
      search.detachChat();
      await pumpEventQueue();
    });
  });

  // Vommet: the live scan of an encrypted room's history (no on-device
  // index, as on web): looking further back after leaving the chat goes on
  // from the scan's last `/messages` token, not from the newest messages.
  testWidgets(
      "after leaving an encrypted chat, the scan goes on from its last "
      "token", (tester) async {
    const id = "!enc:example.com";
    // Real async: the sync writes to the database.
    await tester.runAsync(() async {
      await sync(client, join: {
        id: matrix.JoinedRoomUpdate(
          state: [
            ...roomState(id),
            stateEvent(
                "m.room.encryption", {"algorithm": "m.megolm.v1.aes-sha2"}),
          ],
          // One message (no match), so opening the timeline loads no
          // history: the search alone asks /messages, from p0.
          timeline: matrix.TimelineUpdate(events: [
            matrix.MatrixEvent(
              type: matrix.EventTypes.Message,
              content: {"msgtype": "m.text", "body": "x"},
              senderId: "@bob:example.com",
              eventId: r"$live",
              originServerTs:
                  DateTime.fromMillisecondsSinceEpoch(1700000500000),
            ),
          ], prevBatch: "p0"),
        )
      });
    });
    final room = client.getRoom(id) as MatrixRoom;
    expect(room.isE2EE, isTrue);
    // Pages p0..p29 of 100 events (a page shorter than that is the room's
    // start), one match each.
    final asked = <String?>[];
    Completer<void>? held;
    messagesResponse = (url) async {
      // Only the search's history requests (100 events each): a timeline
      // loading its history (30) or a gap check gets an empty page.
      final from = url.queryParameters["from"];
      final n = int.tryParse(from?.substring(1) ?? "");
      if (url.queryParameters["limit"] != "100" ||
          n == null ||
          !from!.startsWith("p")) {
        return {"start": "x", "chunk": []};
      }
      asked.add(from);
      if (from == "p20") await held?.future;
      return {
        "start": from,
        if (n < 29) "end": "p${n + 1}",
        "chunk": [
          for (var i = 0; i < 100; i++)
            {
              "type": "m.room.message",
              "content": {"msgtype": "m.text", "body": i == 0 ? "hello" : "x"},
              "event_id": "\$p$n-$i",
              "sender": "@bob:example.com",
              "room_id": id,
              "origin_server_ts": 1700000000000 - n * 1000 - i
            }
        ]
      };
    };
    final baseline = Telemetry.timelinesLive;
    // As on web: no on-device index, so the app's own search session for
    // the room is the live scan of its history.
    final index = client.getComponent<MatrixEncryptedSearchIndexComponent>()!;
    client.componentsInternal.remove(index);
    await tester.runAsync(index.onClientClosed);
    final search = InChatSearch(room, debounce: Duration.zero);
    // The scan pages through real (stubbed) requests: wait for its matches.
    Future<void> matches(int count) async {
      for (var i = 0; i < 500 && search.results.length < count; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      await pumpEventQueue();
    }

    await tester.runAsync(() async {
      search.attachChat();
      search.open();
      search.text.text = "hello";
      search.onTextChanged("hello");
      await matches(10);
      expect(asked.toSet(), {for (var n = 0; n < 10; n++) "p$n"},
          reason: "a scan asks for up to 10 pages");
      expect(search.results, hasLength(10));
      expect(room.timeline, isNotNull, reason: "the scan holds it");
      search.detachChat();
      await pumpEventQueue();
      expect(room.timeline, isNull, reason: "the chat went");
      expect(Telemetry.timelinesLive, baseline);
      asked.clear();
      search.attachChat();
      search.loadMore();
      await matches(20);
    });
    expect(asked, contains("p10"));
    expect(asked, isNot(contains("p0")),
        reason: "goes on, not from the newest");
    expect(search.results, hasLength(20));
    expect(search.results.map((e) => e.eventId).toSet(), hasLength(20));

    // Closed while the next page (from p20) is still on its way: the
    // session has no token yet, so reopening goes on from p20 too.
    await tester.runAsync(() async {
      held = Completer();
      asked.clear();
      search.loadMore();
      for (var i = 0; i < 500 && !asked.contains("p20"); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(asked, ["p20"]);
      search.close();
      held!.complete();
      await pumpEventQueue();
      expect(room.timeline, isNull, reason: "closing let it go");
      expect(search.results, hasLength(20), reason: "the matches stay");
      search.open();
      await matches(30);
    });
    expect(asked.where((f) => f == "p20"), hasLength(2));
    expect(asked, isNot(contains("p0")),
        reason: "goes on, not from the newest");
    expect(search.results.map((e) => e.eventId).toSet(), hasLength(30));
    await tester.runAsync(() async {
      search.close();
      search.detachChat();
      await pumpEventQueue();
    });
  });

  // Vommet: typing a new term in the room event search replaced its session
  // without closing it, so each replaced one kept the room's timeline.
  testWidgets(
      "typing twice in the room search, then clearing it, closes the "
      "room's timeline", (tester) async {
    final room = client.getRoom(rooms.first) as MatrixRoom;
    final baseline = Telemetry.timelinesLive;
    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(
          theme: ThemeDark.theme,
          home: Material(child: RoomEventSearchWidget(room: room))));
      for (final term in ["he", "hello"]) {
        await tester.enterText(find.byType(TextField), term);
        // The widget's debounce is a second.
        await Future<void>.delayed(const Duration(milliseconds: 1200));
        await tester.pump();
        await pumpEventQueue();
        expect(Telemetry.timelinesLive, baseline + 1, reason: term);
      }
      await tester.enterText(find.byType(TextField), "");
      await tester.pump();
      await pumpEventQueue();
    });
    expect(room.timeline, isNull,
        reason: "clearing the text ends the last session");
    expect(Telemetry.timelinesLive, baseline);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(pumpEventQueue);
    expect(room.timeline, isNull);
    expect(Telemetry.timelinesLive, baseline);
  });

  // Vommet: leaving the room search with a session open lets it go too.
  testWidgets("leaving the room search closes the room's timeline",
      (tester) async {
    final room = client.getRoom(rooms.first) as MatrixRoom;
    final baseline = Telemetry.timelinesLive;
    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(
          theme: ThemeDark.theme,
          home: Material(child: RoomEventSearchWidget(room: room))));
      await tester.enterText(find.byType(TextField), "hello");
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      await tester.pump();
      await pumpEventQueue();
      expect(Telemetry.timelinesLive, baseline + 1);
      await tester.pumpWidget(const SizedBox());
      await pumpEventQueue();
    });
    expect(room.timeline, isNull);
    expect(Telemetry.timelinesLive, baseline);
  });
}
