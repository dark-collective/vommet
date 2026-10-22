// Vommet: a DM invite accepted in the app goes to the top of the DM list.
//
// Operator report (testing-2026-10-08d): someone DM'd them, they accepted
// the invite, and the DM did not move to the top of Direct Messages. Another
// user opens two older DMs (accepted, marked direct, with messages), then
// two new ones: one with a message waiting, one with nothing sent yet. Each
// new invite is accepted through the app's invitation component (the path
// the invite list's Accept button takes) and must end up first in the DM
// list as drawn on the home screen.

import 'dart:convert';
import 'dart:io';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/client/components/invitation/invitation_component.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/notifying_list_builder.dart';
import 'package:implicitly_animated_list/implicitly_animated_list.dart';
import 'package:commet/ui/organisms/home_screen/important_rooms_list.dart';
import 'package:commet/ui/pages/main/main_page.dart';
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

  /// A DM the way Element starts one: trusted_private_chat, is_direct.
  Future<String> createDm(String invitee, {bool encrypted = false}) async =>
      (await call("POST", "/_matrix/client/v3/createRoom", {
        "preset": "trusted_private_chat",
        "is_direct": true,
        "invite": [invitee],
        if (encrypted)
          "initial_state": [
            {
              "type": "m.room.encryption",
              "state_key": "",
              "content": {"algorithm": "m.megolm.v1.aes-sha2"}
            }
          ],
      }))["room_id"] as String;

  /// An encrypted-looking event, as Element's first message in an encrypted
  /// DM arrives before (or without) its key.
  Future<void> sendEncrypted(String room) => call(
          "PUT",
          "/_matrix/client/v3/rooms/${Uri.encodeComponent(room)}/send/"
              "m.room.encrypted/t${DateTime.now().microsecondsSinceEpoch}",
          {
            "algorithm": "m.megolm.v1.aes-sha2",
            "ciphertext": "AwgAEnACgAkLmt6qF84IK++J7UDH2Za1YVchHyprqTqsg",
            "device_id": "TESTDEVICE",
            "sender_key": "IlRMeOPX2e0MurIyfWEucYBRVOEEUMrOHqn/8mLqMjA",
            "session_id": "X3lUlvLELLYxeTx4yOVu6UDpasGEVO0Jbu+QFnm0cKQ"
          });

  Future<void> join(String room) =>
      call("POST", "/_matrix/client/v3/join/${Uri.encodeComponent(room)}", {});

  Future<void> send(String room, String body) => call(
      "PUT",
      "/_matrix/client/v3/rooms/${Uri.encodeComponent(room)}/send/"
          "m.room.message/t${DateTime.now().microsecondsSinceEpoch}",
      {"msgtype": "m.text", "body": body});

  Future<void> setDirect(Map<String, List<String>> direct) => call(
      "PUT",
      "/_matrix/client/v3/user/${Uri.encodeComponent(userId)}"
          "/account_data/m.direct",
      direct);
}

/// Room ids of the DM rows on the home screen, top to bottom.
List<String> _drawnDmOrder(WidgetTester tester, Client client) {
  final prefix = "DirectMessagesList-${client.identifier}:";
  final rows = find
      .descendant(
          of: find.byType(ImportantRoomsList),
          matching: find.byWidgetPredicate((w) =>
              w.key is ValueKey<String> &&
              (w.key as ValueKey<String>).value.startsWith(prefix)))
      .evaluate()
      .toList();
  final ids = <(double, String)>[
    for (final e in rows)
      (
        (e.renderObject as RenderBox).localToGlobal(Offset.zero).dy,
        ((e.widget.key as ValueKey<String>).value).substring(prefix.length)
      )
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  return ids.map((e) => e.$2).toList();
}

Future<void> _acceptAndExpectOnTop(WidgetTester tester, App app, Client client,
    String roomId, String label) async {
  final invites = client.getComponent<InvitationComponent>()!;
  await tester.waitFor(() => invites.invitations.any((i) => i.roomId == roomId),
      timeout: const Duration(seconds: 30), skipPumpAndSettle: true);
  await invites.acceptInvitation(
      invites.invitations.firstWhere((i) => i.roomId == roomId));

  try {
    await tester.waitFor(
        () => _drawnDmOrder(tester, client).firstOrNull == roomId,
        timeout: const Duration(seconds: 30));
  } catch (_) {
    final room = client.getRoom(roomId);
    final dms = client.getComponent<DirectMessagesComponent>();
    final main = tester.state<MainPageState>(find.byType(MainPage));
    // ignore: avoid_print
    print("DMORDER $label: drawn order ${_drawnDmOrder(tester, client)}, "
        "expected $roomId first; joined=${room != null} "
        "isDM=${room == null ? null : dms?.isRoomDirectMessage(room)} "
        "inComponentList=${dms?.directMessageRooms.any((r) => r.identifier == roomId)} "
        "inAggregate=${app.clientManager.directMessages.directMessageRooms.any((r) => r.identifier == roomId)} "
        "inHomeList=${main.directMessages.any((r) => r.identifier == roomId)} "
        "favorite=${room?.isFavorite} ts=${room?.lastEventTimestamp}");
    if (room is MatrixRoom) {
      final mx = room.matrixRoom;
      final member = mx.getState("m.room.member", mx.client.userID!);
      // ignore: avoid_print
      print(
          "DMORDER mx: sdkLast=${mx.lastEvent?.type}@${mx.lastEvent?.originServerTs} "
          "member=${member.runtimeType} membership=${mx.membership} "
          "stateTypes=${mx.states.keys.toList()}");
    }
    for (final w in find
        .byWidgetPredicate((w) => w is NotifyingListBuilder)
        .evaluate()
        .map((e) => e.widget as dynamic)) {
      // ignore: avoid_print
      print(
          "DMORDER builder sameAsHomeDMs=${identical(w.list, main.directMessages)} "
          "listLen=${w.list.length} sorted=${w.sortFunction != null}");
    }
    for (final e in find
        .byWidgetPredicate((w) => w is NotifyingListBuilder)
        .evaluate()) {
      final st = (e as StatefulElement).state as dynamic;
      // ignore: avoid_print
      print(
          "DMORDER state mounted=${st.mounted} items=${(st.items as List).length} "
          "subs=${(st.subs as List).length}");
    }
    for (final w in find
        .byWidgetPredicate((w) => w is SliverImplicitlyAnimatedList)
        .evaluate()
        .map((e) => e.widget as dynamic)) {
      // ignore: avoid_print
      print("DMORDER sliver items=${w.itemData.length} "
          "hasNew=${(w.itemData as List).any((r) => r is Room && r.identifier == roomId)}");
    }
  }
  // Hold the order for a few seconds: a late re-sort must not move it down.
  await Future.delayed(const Duration(seconds: 5));
  await tester.pump();
  // ignore: avoid_print
  print("DMORDER $label result: drawn=${_drawnDmOrder(tester, client)} "
      "ts=${client.getRoom(roomId)?.lastEventTimestamp}");
  expect(_drawnDmOrder(tester, client).firstOrNull, roomId,
      reason: "$label: the accepted DM is drawn first in Direct Messages");
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('DM order: an accepted DM invite goes to the top',
      (WidgetTester tester) async {
    final tag = RandomUtils.getRandomString(6).toLowerCase();
    final base = Uri.https(tester.homeserver);

    final me = _Api(base);
    await me.login(tester.username, tester.password);
    final friend = _Api(base);
    await friend.register("dmorder$tag");

    // Two older DMs, accepted and marked direct, each with a message.
    final older = <String>[];
    for (var i = 0; i < 2; i++) {
      final room = await friend.createDm(me.userId);
      await me.join(room);
      await friend.send(room, "older $i");
      older.add(room);
    }
    await me.setDirect({
      friend.userId: older,
    });

    final app = await tester.setupApp();
    await tester.pumpWidget(app);
    await tester.login(app);
    await tester.pumpAndSettle();

    final client = app.clientManager.clients.first;
    await tester.waitFor(
        () => older.every((r) => _drawnDmOrder(tester, client).contains(r)),
        timeout: const Duration(seconds: 60));

    // A new DM with a message already waiting (the reported case).
    await Future.delayed(const Duration(seconds: 2));
    final withMessage = await friend.createDm(me.userId);
    await friend.send(withMessage, "hey, new DM");
    await _acceptAndExpectOnTop(
        tester, app, client, withMessage, "with message");

    // An encrypted DM whose first message can't be decrypted (yet).
    await Future.delayed(const Duration(seconds: 2));
    final encrypted = await friend.createDm(me.userId, encrypted: true);
    await friend.sendEncrypted(encrypted);
    await _acceptAndExpectOnTop(tester, app, client, encrypted, "encrypted");

    // A new DM where nothing has been said yet.
    await Future.delayed(const Duration(seconds: 2));
    final empty = await friend.createDm(me.userId);
    await _acceptAndExpectOnTop(tester, app, client, empty, "no message yet");
  });
}
