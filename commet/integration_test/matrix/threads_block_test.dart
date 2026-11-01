// Vommet: the room's thread list, read state per thread, and blocking.
//
// Another user starts two threads in a shared room. The Threads panel must
// list both with their reply counts; a thread opened from the list shows its
// root message (Tuwunel leaves out the relations API's `original_event`, so
// the root is fetched separately) and closes back to the list.
//
// With "Read state per thread" set to All threads (the default is Threads I'm
// in, which would mark these threads read with the room), opening a thread
// sends a receipt for that thread only: the opened thread loses its unread dot, the other keeps it,
// and a new reply brings the dot back.
//
// With "Block users" on, blocking the other user (the account's ignore
// list) hides their message already on screen, keeps out what they send
// while blocked, and unblocking shows the old message again.

import 'dart:convert';
import 'dart:io';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/threads/thread_component.dart';
import 'package:commet/client/components/user_blocking/user_blocking_component.dart';
import 'package:commet/client/matrix/components/threads/matrix_thread_timeline.dart';
import 'package:commet/client/matrix/components/threads/thread_read_scope.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/client/matrix/matrix_timeline.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/organisms/chat/chat.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:commet/utils/rng.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:matrix/matrix.dart' as matrix;

import '../extensions/common_flows.dart';
import '../extensions/wait_for.dart';

class _Api {
  _Api(this.base);
  final Uri base;
  final HttpClient _http = HttpClient();
  String? token;
  late String userId;

  Future<Map<String, dynamic>> call(String method, String path,
      [Object? body]) async {
    var request = await _http.openUrl(method, base.resolve(path));
    request.headers.contentType = ContentType.json;
    if (token != null) request.headers.add("Authorization", "Bearer $token");
    if (body != null) request.write(jsonEncode(body));
    var response = await request.close();
    var text = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      throw Exception("$method $path -> ${response.statusCode} $text");
    }
    return jsonDecode(text) as Map<String, dynamic>;
  }

  Future<void> login(String user, String password) async {
    var result = await call("POST", "/_matrix/client/v3/login", {
      "type": "m.login.password",
      "identifier": {"type": "m.id.user", "user": user},
      "password": password,
    });
    token = result["access_token"] as String;
    userId = result["user_id"] as String;
  }

  Future<void> register(String name) async {
    var r = await call("POST", "/_matrix/client/v3/register", {
      "username": name,
      "password": "pw-$name",
      "auth": {"type": "m.login.dummy"},
    });
    token = r["access_token"] as String;
    userId = r["user_id"] as String;
  }

  Future<String> createRoom(String name, String invitee) async =>
      (await call("POST", "/_matrix/client/v3/createRoom", {
        "preset": "private_chat",
        "name": name,
        "invite": [invitee],
      }))["room_id"] as String;

  Future<void> join(String room) =>
      call("POST", "/_matrix/client/v3/join/${Uri.encodeComponent(room)}", {});

  Future<String> _send(String room, Map<String, dynamic> content) async =>
      (await call(
          "PUT",
          "/_matrix/client/v3/rooms/${Uri.encodeComponent(room)}/send/"
              "m.room.message/t${DateTime.now().microsecondsSinceEpoch}",
          content))["event_id"] as String;

  Future<String> send(String room, String body) =>
      _send(room, {"msgtype": "m.text", "body": body});

  /// A thread reply the way Element sends one.
  Future<String> reply(String room, String root, String body) => _send(room, {
        "msgtype": "m.text",
        "body": body,
        "m.relates_to": {
          "rel_type": "m.thread",
          "event_id": root,
          "is_falling_back": true,
          "m.in_reply_to": {"event_id": root},
        },
      });

  Future<void> redact(String room, String eventId) => call(
      "PUT",
      "/_matrix/client/v3/rooms/${Uri.encodeComponent(room)}/redact/"
          "${Uri.encodeComponent(eventId)}/r${DateTime.now().microsecondsSinceEpoch}",
      {});

  Future<Map<String, dynamic>> accountData(String type) => call(
      "GET",
      "/_matrix/client/v3/user/${Uri.encodeComponent(userId)}"
          "/account_data/$type");
}

Finder _thread(String rootId) => find.byKey(ValueKey("thread-$rootId"));

bool _hasUnreadDot(String rootId) => find
    .descendant(
        of: _thread(rootId),
        matching: find.byKey(const ValueKey("thread-unread-dot")))
    .evaluate()
    .isNotEmpty;

bool _shows(String text) =>
    find.textContaining(text, findRichText: true).evaluate().isNotEmpty;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Threads list, read state per thread, and blocking',
      (WidgetTester tester) async {
    final tag = RandomUtils.getRandomString(6).toLowerCase();
    final base = Uri.https(tester.homeserver);

    final me = _Api(base);
    await me.login(tester.username, tester.password);
    final friend = _Api(base);
    await friend.register("threads$tag");

    final roomId = await friend.createRoom("Threads $tag", me.userId);
    await me.join(roomId);
    final rootA = await friend.send(roomId, "Root A $tag");
    final replyA1 = await friend.reply(roomId, rootA, "A reply 1 $tag");
    await friend.reply(roomId, rootA, "A reply 2 $tag");
    final rootB = await friend.send(roomId, "Root B $tag");
    await friend.reply(roomId, rootB, "B reply 1 $tag");
    // A thread whose root was deleted before anyone replied.
    final rootC = await friend.send(roomId, "Root C $tag");
    await friend.redact(roomId, rootC);

    final app = await tester.setupApp();
    await preferences.experimentBlockUsers.set(true);
    await tester.pumpWidget(app);
    await tester.login(app);
    await tester.pumpAndSettle();
    // The test binding has no lifecycle state, and Vommet only sends read
    // receipts while the app is in the foreground.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

    final Client client = app.clientManager.clients.first;
    await tester.waitFor(() => client.hasRoom(roomId),
        timeout: const Duration(seconds: 60));
    // All threads, on this client only (no account data write: the test
    // account keeps the built-in default for other tests).
    final mx = (client.getRoom(roomId) as MatrixRoom).matrixRoom.client;
    mx.accountData[ThreadReadScopes.type] = matrix.BasicEvent(
        type: ThreadReadScopes.type,
        content: {"default": ThreadReadScope.all.name});
    EventBus.doOpenRoom(roomId, clientId: client.identifier);
    await tester.waitFor(() => _shows("Root B $tag"),
        timeout: const Duration(seconds: 30));

    // The list: both threads, newest activity first, with reply counts.
    EventBus.openThreadsList.add(null);
    await tester.waitFor(
        () =>
            _thread(rootA).evaluate().isNotEmpty &&
            _thread(rootB).evaluate().isNotEmpty,
        timeout: const Duration(seconds: 30));
    expect(
        find.descendant(of: _thread(rootA), matching: find.text("2 replies")),
        findsOneWidget);
    expect(find.descendant(of: _thread(rootB), matching: find.text("1 reply")),
        findsOneWidget);
    final aTop = tester.getTopLeft(_thread(rootA)).dy;
    final bTop = tester.getTopLeft(_thread(rootB)).dy;
    expect(bTop, lessThan(aTop), reason: "newest activity first");
    expect(_thread(rootC), findsNothing,
        reason: "a deleted root with no replies is a deleted thread");

    // Nothing read yet: both threads are unread.
    expect(_hasUnreadDot(rootA), isTrue);
    expect(_hasUnreadDot(rootB), isTrue);

    // Open thread B from the list: its root shows in the thread view (as
    // well as in the main timeline), and its replies.
    await tester.tap(_thread(rootB));
    await tester.waitFor(
        () =>
            _shows("B reply 1 $tag") &&
            find
                    .textContaining("Root B $tag", findRichText: true)
                    .evaluate()
                    .length >=
                2,
        timeout: const Duration(seconds: 30));

    // Reading it sends a receipt for thread B only.
    final mxRoom = (client.getRoom(roomId) as MatrixRoom).matrixRoom;
    await tester.waitFor(
        () => mxRoom.receiptState.byThread[rootB]?.latestOwnReceipt != null,
        timeout: const Duration(seconds: 30));
    expect(mxRoom.receiptState.byThread[rootA]?.latestOwnReceipt, isNull);

    // Closing goes back to the list, where only A is still unread.
    EventBus.closeThread.add(null);
    await tester.waitFor(() => _thread(rootA).evaluate().isNotEmpty,
        timeout: const Duration(seconds: 30));
    await tester.waitFor(() => !_hasUnreadDot(rootB),
        timeout: const Duration(seconds: 30));
    expect(_hasUnreadDot(rootA), isTrue,
        reason: "reading the room and thread B leaves thread A unread");

    // A new reply in B marks it unread again.
    await friend.reply(roomId, rootB, "B reply 2 $tag");
    await tester.waitFor(() => _hasUnreadDot(rootB),
        timeout: const Duration(seconds: 30));
    expect(
        find.descendant(of: _thread(rootB), matching: find.text("2 replies")),
        findsOneWidget);

    // My threads: I haven't replied anywhere.
    await tester.tap(find.byKey(const ValueKey("thread-filter-mine")));
    await tester.waitFor(
        () => find.text("No threads of yours").evaluate().isNotEmpty,
        timeout: const Duration(seconds: 30));
    await tester.tap(find.byKey(const ValueKey("thread-filter-all")));
    await tester.waitFor(() => _thread(rootA).evaluate().isNotEmpty,
        timeout: const Duration(seconds: 30));

    // Open thread A; a reply that arrives while it's open joins the others
    // instead of replacing the newest one (the root, re-announced by the
    // main timeline, used to overwrite it).
    await tester.tap(_thread(rootA));
    // Only the open thread's view counts: the main timeline's thread card
    // quotes replies too.
    Finder inThread(String text) => find.descendant(
        of: find.byWidgetPredicate((w) => w is Chat && w.threadId == rootA),
        matching: find.textContaining(text, findRichText: true));
    bool threadShows(String text) => inThread(text).evaluate().isNotEmpty;
    await tester.waitFor(
        () => threadShows("A reply 1 $tag") && threadShows("A reply 2 $tag"),
        timeout: const Duration(seconds: 30));
    await friend.reply(roomId, rootA, "A reply 3 $tag");
    await tester.waitFor(() => threadShows("A reply 3 $tag"),
        timeout: const Duration(seconds: 30));
    await tester.pump(const Duration(milliseconds: 500));
    expect(threadShows("A reply 1 $tag"), isTrue);
    expect(threadShows("A reply 2 $tag"), isTrue);
    double top(String text) => tester.getTopLeft(inThread(text).first).dy;
    expect(top("Root A $tag"), lessThan(top("A reply 1 $tag")),
        reason: "the root heads the thread");
    expect(top("A reply 1 $tag"), lessThan(top("A reply 2 $tag")));
    expect(top("A reply 2 $tag"), lessThan(top("A reply 3 $tag")),
        reason: "oldest reply at the top, newest at the bottom");

    // The room timeline announces thread events again as it pages through
    // messages a thread already loaded; the thread must not list them twice.
    // Driven on a thread timeline of our own: announcing on the room
    // timeline's stream would also reach the room view behind it.
    final roomTimeline = client.getRoom(roomId)!.timeline! as MatrixTimeline;
    final threads = client.getComponent<ThreadsComponent>()!;
    final thread = (await threads.getThreadTimeline(
        roomTimeline: roomTimeline,
        threadRootEventId: rootA))! as MatrixThreadTimeline;
    for (final id in [replyA1, rootA]) {
      final i = roomTimeline.events.indexWhere((e) => e.eventId == id);
      expect(i, isNot(-1), reason: "$id is in the room timeline");
      thread.onMainTimelineEventAdded(i);
    }
    final ids = thread.events.map((e) => e.eventId).toList();
    expect(ids.toSet().length, ids.length,
        reason: "a re-announced message isn't listed twice: $ids");
    expect(ids.last, rootA, reason: "the root stays the oldest");
    await thread.close();
    EventBus.closeThread.add(null);
    await tester.waitFor(() => _thread(rootA).evaluate().isNotEmpty,
        timeout: const Duration(seconds: 30));

    // Blocking hides the message on screen and keeps new ones out.
    await tester.tap(find.byKey(const ValueKey("threads-panel-close")));
    await friend.send(roomId, "Hello before block $tag");
    await tester.waitFor(() => _shows("Hello before block $tag"),
        timeout: const Duration(seconds: 30));

    final blocking = client.getComponent<UserBlockingComponent>()!;
    await blocking.block(friend.userId);
    await tester.waitFor(() => !_shows("Hello before block $tag"),
        timeout: const Duration(seconds: 30));
    final ignored = await me.accountData("m.ignored_user_list");
    expect((ignored["ignored_users"] as Map).containsKey(friend.userId), isTrue,
        reason: "blocking writes the account's ignore list");

    await friend.send(roomId, "Sent while blocked $tag");
    await Future.delayed(const Duration(seconds: 8));
    await tester.pump();
    expect(_shows("Sent while blocked $tag"), isFalse);

    await blocking.unblock(friend.userId);
    await tester.waitFor(() => _shows("Hello before block $tag"),
        timeout: const Duration(seconds: 30));
    expect(blocking.isBlocked(friend.userId), isFalse);
  });
}
