// Vommet: encryption markers and direct-message trust warnings, end to end
// against the CI homeserver (Vommet issues 130 and 131).
//
// A throwaway "friend" account talks to the app's user:
// * an unencrypted room shows the grey marker and "Send an unencrypted
//   message"; an encrypted DM shows no marker and "Send an encrypted message";
// * a friend who never set up secure messaging gets the "can't confirm"
//   banner, "Let them know" drafts a message, and the banner can be dismissed;
// * when the friend resets their identity, the DM shows the red shield and
//   the "identity changed" strip, and "It was them" clears it;
// * sending text that is a real recovery key stops at the paste guard.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:commet/client/client.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/encryption_marker.dart';
import 'package:commet/ui/atoms/room_header.dart';
import 'package:commet/ui/molecules/dm_trust_banner.dart';
import 'package:commet/ui/molecules/message_input.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:commet/utils/rng.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart' as matrix;

import '../extensions/common_flows.dart';
import '../extensions/wait_for.dart';

class _Api {
  _Api(this.base);
  final Uri base;
  final HttpClient _http = HttpClient();
  String? token;
  late String userId;
  late String password;

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

  Future<void> login(String user, String pw) async {
    var result = await call("POST", "/_matrix/client/v3/login", {
      "type": "m.login.password",
      "identifier": {"type": "m.id.user", "user": user},
      "password": pw,
    });
    token = result["access_token"] as String;
    userId = result["user_id"] as String;
    password = pw;
  }

  Future<void> register(String name) async {
    password = "pw-$name";
    var r = await call("POST", "/_matrix/client/v3/register", {
      "username": name,
      "password": password,
      "auth": {"type": "m.login.dummy"},
    });
    token = r["access_token"] as String;
    userId = r["user_id"] as String;
  }

  Future<String> createRoom(
          {required String invitee,
          bool direct = false,
          bool encrypted = false}) async =>
      (await call("POST", "/_matrix/client/v3/createRoom", {
        "preset": direct ? "trusted_private_chat" : "private_chat",
        if (direct) "is_direct": true,
        "invite": [invitee],
        if (!direct) "name": "trust-it room",
        if (encrypted)
          "initial_state": [
            {
              "type": "m.room.encryption",
              "state_key": "",
              "content": {"algorithm": "m.megolm.v1.aes-sha2"}
            }
          ],
      }))["room_id"] as String;

  Future<void> join(String room) =>
      call("POST", "/_matrix/client/v3/join/${Uri.encodeComponent(room)}", {});

  Future<void> setDirect(Map<String, List<String>> direct) => call(
      "PUT",
      "/_matrix/client/v3/user/${Uri.encodeComponent(userId)}"
          "/account_data/m.direct",
      direct);
}

/// Sets up (or, with an existing identity, wipes and replaces) secure
/// messaging on a test client the way a fresh "set up" would: new secret
/// storage, new cross-signing keys, no key backup.
Future<void> _resetIdentity(matrix.Client client) async {
  final done = Completer<void>();
  client.encryption!.bootstrap(onUpdate: (b) async {
    try {
      switch (b.state) {
        case BootstrapState.askWipeSsss:
          b.wipeSsss(true);
        case BootstrapState.askUseExistingSsss:
          b.useExistingSsss(false);
        case BootstrapState.askBadSsss:
          b.ignoreBadSecrets(true);
        case BootstrapState.askUnlockSsss:
          b.unlockedSsss();
        case BootstrapState.askNewSsss:
          await b.newSsss();
        case BootstrapState.askWipeCrossSigning:
          await b.wipeCrossSigning(true);
        case BootstrapState.askSetupCrossSigning:
          await b.askSetupCrossSigning(
              setupMasterKey: true,
              setupSelfSigningKey: true,
              setupUserSigningKey: true);
        case BootstrapState.askWipeOnlineKeyBackup:
          b.wipeOnlineKeyBackup(true);
        case BootstrapState.askSetupOnlineKeyBackup:
          await b.askSetupOnlineKeyBackup(false);
        case BootstrapState.done:
          if (!done.isCompleted) done.complete();
        case BootstrapState.error:
          if (!done.isCompleted) done.completeError("bootstrap failed");
        default:
          break;
      }
    } catch (e) {
      if (!done.isCompleted) done.completeError(e);
    }
  });
  await done.future.timeout(const Duration(seconds: 90));
}

Future<void> _openRoom(
    WidgetTester tester, Client client, String roomId) async {
  await tester.waitFor(() => client.getRoom(roomId) != null,
      timeout: const Duration(seconds: 60));
  EventBus.doOpenRoom(roomId, clientId: client.identifier);
  await tester.waitFor(() => find.byType(HeaderView).evaluate().isNotEmpty,
      timeout: const Duration(seconds: 30));
  await tester.pumpAndSettle();
}

Finder _inHeader(Finder matching) =>
    find.descendant(of: find.byType(HeaderView), matching: matching);

Future<void> _refreshKeys(
    WidgetTester tester, matrix.Client mx, String userId) async {
  await mx.updateUserDeviceKeys(additionalUsers: {userId});
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Encryption markers: unencrypted room vs encrypted DM',
      (WidgetTester tester) async {
    final tag = RandomUtils.getRandomString(6).toLowerCase();
    final base = Uri.https(tester.homeserver);
    final me = _Api(base);
    await me.login(tester.username, tester.password);
    final friend = _Api(base);
    await friend.register("trustmark$tag");

    final plainRoom = await friend.createRoom(invitee: me.userId);
    await me.join(plainRoom);
    final dm = await friend.createRoom(
        invitee: me.userId, direct: true, encrypted: true);
    await me.join(dm);
    await me.setDirect({
      friend.userId: [dm]
    });

    final app = await tester.setupApp();
    await preferences.experimentEncryptionMarkers.set(true);
    await tester.pumpWidget(app);
    await tester.login(app);
    await tester.pumpAndSettle();
    final client = app.clientManager.clients.first;

    await _openRoom(tester, client, plainRoom);
    expect(_inHeader(find.byIcon(Icons.no_encryption_outlined)), findsOneWidget,
        reason: "an unencrypted room shows the grey marker after its name");
    expect(find.text("Send an unencrypted message"), findsOneWidget);

    // Tapping the marker explains it.
    await tester.tap(_inHeader(find.byIcon(Icons.no_encryption_outlined)));
    await tester.pumpAndSettle();
    expect(find.text("This room is not encrypted"), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    await _openRoom(tester, client, dm);
    await tester.waitFor(
        () => find.text("Send an encrypted message").evaluate().isNotEmpty,
        timeout: const Duration(seconds: 30));
    expect(_inHeader(find.byIcon(Icons.no_encryption_outlined)), findsNothing,
        reason: "an encrypted DM shows no marker");
    expect(_inHeader(find.byIcon(Icons.gpp_maybe)), findsNothing);
  });

  testWidgets('Trust: "can\'t confirm" banner for someone not set up',
      (WidgetTester tester) async {
    final tag = RandomUtils.getRandomString(6).toLowerCase();
    final base = Uri.https(tester.homeserver);
    final me = _Api(base);
    await me.login(tester.username, tester.password);
    final friend = _Api(base);
    await friend.register("trustnone$tag");
    // A device with encryption keys, but no secure messaging (no master key).
    final friendDevice = await tester.createTestClient(
        user: "trustnone$tag", password: friend.password);
    addTearDown(() => friendDevice.dispose());

    final dm = await friend.createRoom(
        invitee: me.userId, direct: true, encrypted: true);
    await me.join(dm);
    await me.setDirect({
      friend.userId: [dm]
    });

    final app = await tester.setupApp();
    await preferences.experimentDmTrustWarnings.set(true);
    await tester.pumpWidget(app);
    await tester.login(app);
    await tester.pumpAndSettle();
    final client = app.clientManager.clients.first;
    final mx = (client as dynamic).getMatrixClient() as matrix.Client;

    await _openRoom(tester, client, dm);
    await _refreshKeys(tester, mx, friend.userId);
    await tester.waitFor(
        () => find
            .textContaining("We can't confirm", findRichText: true)
            .evaluate()
            .isNotEmpty,
        timeout: const Duration(seconds: 30));

    // "Let them know" drafts the heads-up into the message box.
    await tester.tap(find.text("Let them know"));
    await tester.pumpAndSettle();
    final input = find.descendant(
        of: find.byType(MessageInput), matching: find.byType(TextField));
    expect(
        (tester.widget<TextField>(input).controller?.text ?? "")
            .contains(secureMessagingHelpUrl),
        isTrue,
        reason: "the drafted message links to the guide");
    // Typing in an encrypted room starts preparing its keys in the
    // background; clear the draft and let that finish, so the teardown
    // doesn't close the database under it.
    await tester.enterText(input, "");
    await tester.pumpAndSettle();
    await Future.delayed(const Duration(seconds: 5));
    await tester.pump();

    // Dismissing it keeps it dismissed for this room.
    await tester.tap(find.descendant(
        of: find.byType(DmTrustBanner), matching: find.byIcon(Icons.close)));
    await tester.pumpAndSettle();
    expect(find.textContaining("We can't confirm"), findsNothing);
  });

  testWidgets('Trust: identity change shows the red warning until accepted',
      (WidgetTester tester) async {
    final tag = RandomUtils.getRandomString(6).toLowerCase();
    final base = Uri.https(tester.homeserver);
    final me = _Api(base);
    await me.login(tester.username, tester.password);
    final friend = _Api(base);
    await friend.register("trustreset$tag");
    final friendDevice = await tester.createTestClient(
        user: "trustreset$tag", password: friend.password);
    addTearDown(() => friendDevice.dispose());
    await _resetIdentity(friendDevice);
    final firstMaster =
        friendDevice.userDeviceKeys[friendDevice.userID]?.masterKey?.publicKey;
    expect(firstMaster, isNotNull,
        reason: "the friend set up secure messaging");

    final dm = await friend.createRoom(
        invitee: me.userId, direct: true, encrypted: true);
    await me.join(dm);
    await me.setDirect({
      friend.userId: [dm]
    });

    final app = await tester.setupApp();
    await preferences.experimentDmTrustWarnings.set(true);
    await preferences.experimentEncryptionMarkers.set(true);
    await tester.pumpWidget(app);
    await tester.login(app);
    await tester.pumpAndSettle();
    final client = app.clientManager.clients.first;
    final mx = (client as dynamic).getMatrixClient() as matrix.Client;

    // First sight: their identity is remembered, nothing is shown.
    await _openRoom(tester, client, dm);
    await _refreshKeys(tester, mx, friend.userId);
    await tester.waitFor(
        () =>
            mx.userDeviceKeys[friend.userId]?.masterKey?.publicKey ==
            firstMaster,
        timeout: const Duration(seconds: 30));
    await tester.pumpAndSettle();
    expect(_inHeader(find.byIcon(Icons.gpp_maybe)), findsNothing);
    expect(find.textContaining("identity changed"), findsNothing);

    // They reset: new identity.
    await _resetIdentity(friendDevice);
    final secondMaster =
        friendDevice.userDeviceKeys[friendDevice.userID]?.masterKey?.publicKey;
    expect(secondMaster, isNot(firstMaster));

    await tester.waitFor(() {
      // Keys normally arrive through sync; refresh too, so the test is quick.
      mx.updateUserDeviceKeys(additionalUsers: {friend.userId});
      return mx.userDeviceKeys[friend.userId]?.masterKey?.publicKey ==
          secondMaster;
    }, timeout: const Duration(seconds: 60));
    // The header and the strip pick it up on the next room update.
    await tester.waitFor(
        () => find.textContaining("identity changed").evaluate().isNotEmpty,
        timeout: const Duration(seconds: 60));
    expect(_inHeader(find.byIcon(Icons.gpp_maybe)), findsOneWidget,
        reason: "the red shield follows their name");

    // "It was them" accepts the new identity.
    await tester.tap(find.text("It was them"));
    await tester.pumpAndSettle();
    await tester.waitFor(
        () => find.textContaining("identity changed").evaluate().isEmpty,
        timeout: const Duration(seconds: 10));
    expect(_inHeader(find.byIcon(Icons.gpp_maybe)), findsNothing);
  });

  testWidgets('Paste guard: a recovery key stops before sending',
      (WidgetTester tester) async {
    final tag = RandomUtils.getRandomString(6).toLowerCase();
    final base = Uri.https(tester.homeserver);
    final me = _Api(base);
    await me.login(tester.username, tester.password);
    final friend = _Api(base);
    await friend.register("trustpaste$tag");
    final room = await friend.createRoom(invitee: me.userId);
    await me.join(room);

    final app = await tester.setupApp();
    await preferences.experimentDmTrustWarnings.set(true);
    await tester.pumpWidget(app);
    await tester.login(app);
    await tester.pumpAndSettle();
    final client = app.clientManager.clients.first;
    await _openRoom(tester, client, room);

    final key = SSSS.encodeRecoveryKey(
        Uint8List.fromList(List.generate(32, (i) => (i * 11 + 5) % 256)));
    final input = find.descendant(
        of: find.byType(MessageInput), matching: find.byType(TextField));
    await tester.tap(input);
    await tester.enterText(input, "my key is $key");
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.text("That looks like a recovery key"), findsOneWidget);
    await tester.tap(find.text("Don't send it"));
    await tester.pumpAndSettle();

    // Nothing was sent; the text is still there to delete.
    expect(tester.widget<TextField>(input).controller?.text, contains(key));
    final mxRoom =
        (client as dynamic).getMatrixClient().getRoomById(room) as matrix.Room;
    final timeline = await mxRoom.getTimeline();
    expect(timeline.events.any((e) => e.body.contains(key)), isFalse,
        reason: "\"Don't send it\" must not send the key");
  });
}
