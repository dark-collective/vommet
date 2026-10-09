// Vommet: the room's thread list, read state per thread, and blocking.
//
// Another user starts two threads in a shared room. The Threads panel must
// list both with their reply counts; a thread opened from the list shows its
// root message (Tuwunel leaves out the relations API's `original_event`, so
// the root is fetched separately) and closes back to the list.
//
// With "Read state per thread" on, opening a thread sends a receipt for that
// thread only: the opened thread loses its unread dot, the other keeps it,
// and a new reply brings the dot back.
//
// With "Block users" on, blocking the other user (the account's ignore
// list) hides their message already on screen, keeps out what they send
// while blocked, and unblocking shows the old message again.

import 'dart:convert';
import 'dart:io';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/user_blocking/user_blocking_component.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/main.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:commet/utils/rng.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

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
    await friend.reply(roomId, rootA, "A reply 1 $tag");
    await friend.reply(roomId, rootA, "A reply 2 $tag");
    final rootB = await friend.send(roomId, "Root B $tag");
    await friend.reply(roomId, rootB, "B reply 1 $tag");

    final app = await tester.setupApp();
    await preferences.experimentThreadReadState.set(true);
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
