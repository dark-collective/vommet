// Vommet: rooms and spaces you were banned from (feat/banned-room-footer).
//
// A moderator bans the test user from a room, then from a space, against the
// test homeserver. The banned room must stay listed and readable with the
// banned footer (and the moderator's reason) in place of the composer; the
// banned space must stay, faded, with its notice, while the rooms inside it
// that you're still in keep their composer. Dismiss forgets each one.

import 'dart:convert';
import 'dart:io';

import 'package:commet/ui/atoms/banned_space_icon.dart';
import 'package:commet/ui/atoms/space_icon.dart';
import 'package:commet/ui/molecules/composer_notice.dart';
import 'package:commet/ui/molecules/message_input.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:commet/utils/rng.dart';
import 'package:flutter_test/flutter_test.dart';

import '../extensions/common_flows.dart';
import '../extensions/wait_for.dart';

class _Api {
  _Api(this.base);
  final Uri base;
  final HttpClient _http = HttpClient();
  String? token;

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
  }

  Future<void> register(String name) async {
    var r = await call("POST", "/_matrix/client/v3/register", {
      "username": name,
      "password": "pw-$name",
      "auth": {"type": "m.login.dummy"},
    });
    token = r["access_token"] as String;
  }

  Future<String> createRoom(String name, {List<String>? children}) async =>
      (await call("POST", "/_matrix/client/v3/createRoom", {
        "preset": "public_chat",
        "name": name,
        if (children != null) "creation_content": {"type": "m.space"},
        if (children != null)
          "initial_state": [
            for (final child in children)
              {
                "type": "m.space.child",
                "state_key": child,
                "content": {
                  "via": [base.host]
                }
              },
          ],
      }))["room_id"] as String;

  Future<void> join(String room) =>
      call("POST", "/_matrix/client/v3/join/${Uri.encodeComponent(room)}", {});

  Future<void> ban(String room, String user, {String? reason}) => call(
      "POST",
      "/_matrix/client/v3/rooms/${Uri.encodeComponent(room)}/ban",
      {"user_id": user, if (reason != null) "reason": reason});

  Future<void> send(String room, String body) => call(
      "PUT",
      "/_matrix/client/v3/rooms/${Uri.encodeComponent(room)}/send/m.room.message/"
          "${DateTime.now().microsecondsSinceEpoch}",
      {"msgtype": "m.text", "body": body});
}

void main() {
  testWidgets('Banned room and space stay until dismissed',
      (WidgetTester tester) async {
    final tag = RandomUtils.getRandomString(6).toLowerCase();
    final base = Uri.https(tester.homeserver);

    final me = _Api(base);
    await me.login(tester.username, tester.password);
    final myId = (await me.call(
        "GET", "/_matrix/client/v3/account/whoami"))["user_id"] as String;

    final mod = _Api(base);
    await mod.register("mod$tag");
    final room = await mod.createRoom("Poketalk $tag");
    final spaceRoom = await mod.createRoom("Trading $tag");
    final space =
        await mod.createRoom("Poke Center $tag", children: [spaceRoom]);
    for (final r in [room, space, spaceRoom]) {
      await me.join(r);
    }
    await me.send(room, "Hey guys, did you know that Vaporeon is $tag");

    final app = await tester.setupApp();
    await tester.pumpWidget(app);
    await tester.login(app);
    await tester.pumpAndSettle();

    final client = app.clientManager.clients.first;
    await tester.waitFor(
        () =>
            client.hasRoom(room) &&
            client.hasRoom(spaceRoom) &&
            client.hasSpace(space),
        timeout: const Duration(seconds: 30),
        skipPumpAndSettle: true);

    // Room ban: the footer replaces the composer, with the reason.
    EventBus.doOpenRoom(room, clientId: client.identifier);
    await tester.waitFor(() => find.byType(MessageInput).evaluate().isNotEmpty,
        timeout: const Duration(seconds: 20));
    await mod.ban(room, myId, reason: "no.");
    await tester.waitFor(
        () =>
            find.text("You were banned from this room.").evaluate().isNotEmpty,
        timeout: const Duration(seconds: 30));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text("Reason: no."), findsOneWidget);
    expect(find.byType(MessageInput), findsNothing);
    expect(client.hasRoom(room), isTrue);
    expect(client.getRoom(room)!.isBanned, isTrue);
    expect(find.textContaining("Vaporeon is $tag"), findsWidgets);

    // Space ban, no reason: the space stays, faded; its rooms are unaffected.
    await mod.ban(space, myId);
    await tester.waitFor(() => client.getSpace(space)?.isBanned == true,
        timeout: const Duration(seconds: 30));
    expect(client.hasRoom(spaceRoom), isTrue);
    expect(client.getRoom(spaceRoom)!.isBanned, isFalse);

    final icon =
        find.byWidgetPredicate((w) => w is SpaceIcon && w.spaceId == space);
    await tester.waitFor(() => icon.evaluate().isNotEmpty,
        timeout: const Duration(seconds: 20));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
        find
                .ancestor(of: icon, matching: find.byType(BannedSpaceIcon))
                .evaluate()
                .isNotEmpty ||
            find
                .descendant(of: icon, matching: find.byType(BannedSpaceIcon))
                .evaluate()
                .isNotEmpty,
        isTrue);
    await tester.tap(icon.first);
    await tester.waitFor(
        () =>
            find.text("You were banned from this space.").evaluate().isNotEmpty,
        timeout: const Duration(seconds: 20));
    final spaceNotice = find.ancestor(
        of: find.text("You were banned from this space."),
        matching: find.byType(ComposerNotice));
    expect(
        find.descendant(
            of: spaceNotice, matching: find.textContaining("Reason")),
        findsNothing);

    // The room inside the banned space still has its composer.
    EventBus.doOpenRoom(spaceRoom, clientId: client.identifier);
    await tester.waitFor(() => find.byType(MessageInput).evaluate().isNotEmpty,
        timeout: const Duration(seconds: 20));

    // Dismiss forgets them; the room you're still in stays.
    await client.getRoom(room)!.dismissBan();
    await client.getSpace(space)!.dismissBan();
    await tester.waitFor(() => !client.hasRoom(room) && !client.hasSpace(space),
        timeout: const Duration(seconds: 20));
    expect(client.hasRoom(spaceRoom), isTrue);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });
}
