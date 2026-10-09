// Vommet issue 129: secure messaging setup (cross-signing + key backup)
// against the real CI homeserver. Every test registers its own fresh
// accounts, so nothing here touches alice/bob or depends on test order.
//
// UI-level: a new account through the own-password path (with the real
// account-password prompt), skipping (both warnings, an interrupted hold),
// an existing account unlocked with its recovery key, and approval from
// another device. SDK-level, on the logged-in app client: replacing the
// key (same identity), "someone used my key" (new identity + backup),
// "make a new key" (keeps the backup), and the safety guarantees (nothing
// existing is ever replaced without consent; a wrong key changes nothing).

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/secure_messaging_state.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/pages/login/login_page.dart';
import 'package:commet/ui/pages/secure_setup/login_password_memory.dart';
import 'package:commet/ui/pages/secure_setup/secure_setup_controller.dart';
import 'package:commet/ui/pages/secure_setup/secure_setup_records.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show databaseFactoryFfi, OpenDatabaseOptions;

import '../extensions/common_flows.dart';
import '../extensions/wait_for.dart';

const _accountPassword = "Correct-Horse-Battery-9";
const _recoveryPassword = "my cat sleeps on the warm radiator";
const _otherRecoveryPassword = "the lantern glows over the quiet harbor";
final _rng = Random();

/// Slowest password-to-key derivation the probe measured (the SDK gives it
/// 10 s; a debug build's unoptimized native library takes 14-17 s here).
int? _passwordKeyMs;

void _log(String s) {
  // ignore: avoid_print
  print("[secure-setup-it] $s");
}

String _uniq(String prefix) =>
    "${prefix}_${DateTime.now().millisecondsSinceEpoch}_${_rng.nextInt(99999)}";

extension _Flows on WidgetTester {
  /// Registers a fresh account (the CI homeserver has open registration).
  Future<String> registerUser(String name) async {
    final r =
        await http.post(Uri.https(homeserver, "/_matrix/client/v3/register"),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({
              "username": name,
              "password": _accountPassword,
              "auth": {"type": "m.login.dummy"},
              "inhibit_login": true,
            }));
    if (r.statusCode != 200) {
      throw Exception("register $name: ${r.statusCode} ${r.body}");
    }
    return jsonDecode(r.body)["user_id"] as String;
  }

  /// Logs in through the login page as [user].
  Future<void> loginAs(App app, String user) async {
    await waitFor(() => find.byType(LoginPage).evaluate().isNotEmpty);
    final inputs = find.byType(TextField);
    await enterText(inputs.at(0), homeserver);
    await pumpAndSettle();
    await enterText(inputs.at(1), user);
    await pumpAndSettle();
    await enterText(inputs.at(2), _accountPassword);
    await pumpAndSettle();
    await tap(find.widgetWithText(ElevatedButton, "Login"));
    await pumpAndSettle();
    await waitFor(() => app.clientManager.isLoggedIn(),
        timeout: const Duration(seconds: 20), skipPumpAndSettle: true);
  }

  /// Pumps frames until [future] completes (long SDK work in a test),
  /// typing the account password into the app's own password dialog
  /// whenever it appears (unless [answerPassword] is off).
  Future<T> pumpUntil<T>(Future<T> future,
      {Duration timeout = const Duration(minutes: 2),
      bool answerPassword = true}) async {
    var done = false;
    T? value;
    Object? error;
    StackTrace? trace;
    future.then((v) {
      value = v;
      done = true;
    }, onError: (Object e, StackTrace s) {
      error = e;
      trace = s;
      done = true;
    });
    final end = DateTime.now().add(timeout);
    while (!done) {
      if (DateTime.now().isAfter(end)) {
        dumpScreen();
        throw TimeoutException("pumpUntil");
      }
      if (answerPassword) await answerPasswordDialog();
      await pump(const Duration(milliseconds: 100));
      await Future.delayed(const Duration(milliseconds: 50));
    }
    if (error != null) Error.throwWithStackTrace(error!, trace!);
    return value as T;
  }

  /// The app's "Authentication Request" dialog: picks the password step and
  /// types the account password, like a user. Returns whether it acted.
  Future<bool> answerPasswordDialog() async {
    if (find.text("Continue with password").evaluate().isNotEmpty) {
      await tap(find.text("Continue with password").last);
      await pump();
      return true;
    }
    final field = _passwordField;
    if (field.evaluate().isNotEmpty &&
        (widget<TextField>(field.last).controller?.text.isEmpty ?? true)) {
      _log("server asked for the account password (UIA)");
      await enterText(field.last, _accountPassword);
      await tap(find.text("Submit").last);
      await pump();
      return true;
    }
    return false;
  }

  /// Closes the password dialog without answering (the app then cancels
  /// the request).
  Future<bool> closePasswordDialog() async {
    final at = find.text("Continue with password").evaluate().isNotEmpty
        ? find.text("Continue with password")
        : _passwordField;
    if (at.evaluate().isEmpty) return false;
    Navigator.of(element(at.last)).pop();
    await pump();
    return true;
  }

  Future<void> run(Duration d) async {
    final end = DateTime.now().add(d);
    while (DateTime.now().isBefore(end)) {
      await pump();
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  Future<void> waitText(String text,
      {Duration timeout = const Duration(seconds: 60)}) async {
    try {
      // Pumps a frame on every check: the test binding doesn't draw the
      // app's async updates (setState after a network call) on its own.
      await waitFor(() => find.text(text).evaluate().isNotEmpty,
          timeout: timeout);
    } catch (_) {
      _log("timed out waiting for \"$text\"");
      dumpScreen();
      rethrow;
    }
  }

  /// What's on screen and what the sign-in setup decides from, so a
  /// failure explains itself.
  void dumpScreen() {
    final texts = <String>{
      for (final e in find.byType(Text).evaluate())
        if ((e.widget as Text).data case final String d when d.isNotEmpty) d,
    };
    _log("on screen: ${texts.take(40).join(" | ")}");
    _log("experimentSecureSetup=${preferences.experimentSecureSetup.value}");
    for (final c in clientManager?.clients ?? const []) {
      if (c is! MatrixClient) continue;
      final mx = c.getMatrixClient();
      _log("client ${mx.userID}: encryption=${mx.encryptionEnabled} "
          "unknownSession=${mx.isUnknownSession} "
          "status=${SecureMessaging.fromClient(mx).state} "
          "skipped=${SecureSetupRecords(mx.userID!).skipped}");
    }
  }

  Future<void> tapText(String text) async {
    await tap(find.text(text).last);
    await pump();
  }

  /// A raw SDK client as another device of [user] (own in-memory database,
  /// answers account-password prompts itself).
  Future<Client> rawDevice(String user,
      {String name = "IT other device"}) async {
    final id = "it-${DateTime.now().microsecondsSinceEpoch}";
    final c = Client(
      id,
      verificationMethods: {KeyVerificationMethod.emoji},
      nativeImplementations: MatrixClient.nativeImplementations,
      database: await MatrixSdkDatabase.init(id,
          database: await databaseFactoryFfi.openDatabase(':memory:',
              options: OpenDatabaseOptions(singleInstance: false)),
          sqfliteFactory: databaseFactoryFfi),
    );
    c.onUiaRequest.stream.listen((uia) {
      if (uia.state == UiaRequestState.waitForUser) {
        uia.completeStage(AuthenticationPassword(
            session: uia.session,
            password: _accountPassword,
            identifier: AuthenticationUserIdentifier(user: user)));
      }
    });
    await c.checkHomeserver(Uri.https(homeserver), checkWellKnown: false);
    await c.login(LoginType.mLoginPassword,
        identifier: AuthenticationUserIdentifier(user: user),
        password: _accountPassword,
        initialDeviceDisplayName: name);
    await c.oneShotSync();
    addTearDown(() => c.dispose(closeDatabase: true));
    return c;
  }
}

final _passwordField = find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.hintText == "Account Password");

Future<String?> _masterKey(Client c) async {
  final r = await c.queryKeys({c.userID!: []});
  return r.masterKeys?[c.userID!]?.keys.values.firstOrNull;
}

Future<String?> _backupVersion(Client c) async {
  try {
    return (await c.getRoomKeysVersionCurrent()).version;
  } on MatrixException catch (e) {
    if (e.error == MatrixError.M_NOT_FOUND) return null;
    rethrow;
  }
}

/// An encrypted room with one message from [c]; the key is uploaded to the
/// backup. Returns (roomId, eventId).
Future<(String, String)> _secretMessage(Client c, String text) async {
  final roomId = await c.createRoom(initialState: [
    StateEvent(
        type: EventTypes.Encryption,
        stateKey: "",
        content: {"algorithm": AlgorithmTypes.megolmV1AesSha2}),
  ]);
  for (var i = 0; i < 100 && c.getRoomById(roomId)?.encrypted != true; i++) {
    await Future.delayed(const Duration(milliseconds: 200));
  }
  final room = c.getRoomById(roomId)!;
  final eventId = (await room.sendTextEvent(text))!;
  await c.encryption!.keyManager.uploadInboundGroupSessions();
  return (roomId, eventId);
}

/// Unlocks [raw]'s secret storage with [input], confirms the device and
/// restores the backup; then decrypts [eventId] and returns its body.
Future<String?> _decryptOnNewDevice(
    Client raw, String input, String roomId, String eventId) async {
  final handle = raw.encryption!.ssss.open(EventTypes.CrossSigningMasterKey);
  await handle.unlock(keyOrPassphrase: input);
  await handle.maybeCacheAll();
  await raw.encryption!.crossSigning.selfSign(openSsss: handle);
  await raw.encryption!.keyManager.loadAllKeys();
  final room = raw.getRoomById(roomId)!;
  final ev =
      Event.fromMatrixEvent(await raw.getOneRoomEvent(roomId, eventId), room);
  final decrypted = await raw.encryption!.decryptRoomEvent(ev);
  return decrypted.type == EventTypes.Message
      ? decrypted.content["body"] as String?
      : null;
}

bool _secretsUnderDefaultKey(Client mx) {
  final keyId = mx.encryption!.ssss.defaultKeyId;
  if (keyId == null) return false;
  for (final type in const [
    EventTypes.CrossSigningMasterKey,
    EventTypes.CrossSigningSelfSigning,
    EventTypes.CrossSigningUserSigning,
    EventTypes.MegolmBackup,
  ]) {
    final enc = mx.accountData[type]?.content["encrypted"];
    if (enc is! Map || !enc.containsKey(keyId)) return false;
  }
  return true;
}

/// App + a fresh logged-in account. [gate]: show the sign-in setup.
Future<(App, MatrixClient, String)> _start(WidgetTester tester, String who,
    {required bool gate}) async {
  final user = _uniq(who);
  final userId = await tester.registerUser(user);
  final app = await tester.setupApp(secureSetup: gate);
  await tester.pumpWidget(app);
  await tester.loginAs(app, user);
  final client = app.clientManager.clients.first as MatrixClient;
  _log("logged in $userId device ${client.getMatrixClient().deviceID}");
  return (app, client, userId);
}

void main() {
  // How long turning a recovery password into a key takes here, through
  // the app's own native implementations (the SDK gives it 10 s).
  testWidgets("probe: recovery password to key timing", (tester) async {
    final ssss = MatrixClient.nativeImplementations;
    for (var i = 0; i < 4; i++) {
      final clock = Stopwatch()..start();
      try {
        await Future.value(ssss.keyFromPassphrase(KeyFromPassphraseArgs(
                passphrase: _recoveryPassword,
                info: PassphraseInfo(
                    iterations: 500000,
                    salt: "probe-salt-$i",
                    algorithm: AlgorithmTypes.pbkdf2,
                    bits: 256))))
            .timeout(const Duration(seconds: 60));
        _log("key from password #$i: ${clock.elapsedMilliseconds} ms");
        _passwordKeyMs = max(_passwordKeyMs ?? 0, clock.elapsedMilliseconds);
      } catch (e) {
        _log("key from password #$i failed after "
            "${clock.elapsedMilliseconds} ms: $e");
        _passwordKeyMs = 1 << 30;
      }
    }
  });

  testWidgets("new account: own password, real password prompt, confirm",
      (tester) async {
    if ((_passwordKeyMs ?? 1 << 30) > 8000) {
      // Not a pass: the SDK would time out before the key exists.
      markTestSkipped("deriving a key from a password takes "
          "${_passwordKeyMs} ms here (debug build), over the SDK's 10 s");
      return;
    }
    final (app, client, userId) = await _start(tester, "sec_new", gate: true);
    final mx = client.getMatrixClient();

    // The login password is known right after a password sign-in only.
    expect(LoginPasswordMemory.isLoginPassword(userId, _accountPassword), true);
    expect(
        LoginPasswordMemory.isLoginPassword(userId, "something else"), false);

    await tester.waitText("Keep your messages safe");
    await tester.tapText("Set up  ·  about 2 minutes");
    await tester.waitText("How do you want to save your recovery key?");
    await tester.tapText("Choose my own password");
    await tester.tapText("Continue");
    await tester.waitText("Choose a recovery password");

    // Reusing the login password is warned about and blocked.
    await tester.enterText(find.byType(TextField).first, _accountPassword);
    await tester.run(const Duration(milliseconds: 500));
    expect(find.text("This is your login password"), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, _recoveryPassword);
    await tester.run(const Duration(milliseconds: 500));
    expect(find.text("This is your login password"), findsNothing);
    await tester.tapText("Continue");

    // The server may ask for the account password: the real dialog.
    var askedPassword = false;
    final until = DateTime.now().add(const Duration(seconds: 90));
    while (find.text("Type it once more").evaluate().isEmpty) {
      if (DateTime.now().isAfter(until)) fail("setup didn't reach confirm");
      if (await tester.answerPasswordDialog()) askedPassword = true;
      await tester.pump(const Duration(milliseconds: 100));
      await Future.delayed(const Duration(milliseconds: 50));
    }
    _log("password dialog shown: $askedPassword");
    await tester.waitText("Type it once more",
        timeout: const Duration(seconds: 90));

    // The confirm step rejects a wrong answer and accepts the right one.
    await tester.enterText(find.byType(TextField).first, "not it at all");
    await tester.tapText("Check");
    await tester.run(const Duration(milliseconds: 500));
    expect(find.text("That's not the same password."), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, _recoveryPassword);
    await tester.tapText("Check");
    await tester.waitText("You're all set");
    expect(
        LoginPasswordMemory.isLoginPassword(userId, _accountPassword), isNull,
        reason: "the login password hash is gone after setup");

    // What the server and the SDK now say.
    expect(mx.encryption!.crossSigning.enabled, true);
    expect(mx.encryption!.keyManager.enabled, true);
    expect(await _masterKey(mx), isNotNull);
    expect(await _backupVersion(mx), isNotNull);
    expect(_secretsUnderDefaultKey(mx), true,
        reason: "master, self-signing, user-signing and backup keys stored");
    final ctl = SecureSetupController(client);
    expect(await ctl.checkKey(_recoveryPassword), true);
    expect(await ctl.checkKey("wrong password"), false);
    expect(SecureMessaging.of(client).state, SecureMessagingState.ready);

    await tester.tapText("Start chatting");
    await tester.run(const Duration(seconds: 1));
    expect(find.text("You're all set"), findsNothing);
    await app.clientManager.close();
  });

  testWidgets("skipping needs both warnings and a full hold", (tester) async {
    final (app, client, userId) = await _start(tester, "sec_skip", gate: true);
    final records = SecureSetupRecords(userId);
    await tester.waitText("Keep your messages safe");

    // Warning 1 → "Go back and set up": not skipped.
    await tester.tapText("Skip for now");
    await tester.waitText("Skip secure messaging?");
    await tester.tapText("Go back and set up");
    await tester.run(const Duration(milliseconds: 500));
    expect(find.text("Keep your messages safe"), findsOneWidget);
    expect(records.skipped, false);

    // Warning 2, a hold let go early: not skipped.
    await tester.tapText("Skip for now");
    await tester.waitText("Skip secure messaging?");
    await tester.tapText("Skip anyway");
    await tester.waitText("This is for developers");
    var g =
        await tester.startGesture(tester.getCenter(find.text("Hold to skip")));
    await tester.run(const Duration(milliseconds: 600));
    await g.up();
    await tester.run(const Duration(milliseconds: 800));
    expect(find.text("This is for developers"), findsOneWidget);
    expect(records.skipped, false);

    // A full hold skips: setup closes, the reminder banner shows.
    g = await tester.startGesture(tester.getCenter(find.text("Hold to skip")));
    await tester.run(const Duration(milliseconds: 2600));
    await g.up();
    await tester.run(const Duration(seconds: 2));
    expect(records.skipped, true);
    expect(find.text("Keep your messages safe"), findsNothing);
    expect(find.text("Your messages aren't backed up"), findsWidgets);
    expect(await _masterKey(client.getMatrixClient()), isNull,
        reason: "skipping creates nothing");
    await app.clientManager.close();
  });

  testWidgets("existing account: recovery key on a new device restores history",
      (tester) async {
    final user = _uniq("sec_exist");
    await tester.registerUser(user);
    final first = await tester.rawDevice(user, name: "First device");
    final recoveryKey = await first.initCryptoIdentity();
    final (roomId, eventId) = await _secretMessage(first, "hello from before");

    final app = await tester.setupApp(secureSetup: true);
    await tester.pumpWidget(app);
    await tester.loginAs(app, user);
    final client = app.clientManager.clients.first as MatrixClient;
    final mx = client.getMatrixClient();

    await tester.waitText("Is this you?", timeout: const Duration(seconds: 90));
    await tester.tapText("Enter recovery key or phrase");
    await tester.waitText("Enter your recovery key");
    await tester.enterText(find.byType(TextField).first, recoveryKey);
    await tester.tapText("Unlock my messages");
    await tester.waitText("You're all set",
        timeout: const Duration(seconds: 120));

    expect(mx.isUnknownSession, false, reason: "this device is verified");
    final room = mx.getRoomById(roomId)!;
    final ev =
        Event.fromMatrixEvent(await mx.getOneRoomEvent(roomId, eventId), room);
    final decrypted = await mx.encryption!.decryptRoomEvent(ev);
    expect(decrypted.content["body"], "hello from before",
        reason: "keys restored from the backup");
    await app.clientManager.close();
  });

  testWidgets("approve from another device", (tester) async {
    final user = _uniq("sec_approve");
    await tester.registerUser(user);
    final first = await tester.rawDevice(user, name: "First device");
    await first.initCryptoIdentity();
    final (roomId, eventId) = await _secretMessage(first, "approved history");

    // The first device accepts whatever verification arrives.
    first.onKeyVerificationRequest.stream.listen((req) async {
      req.onUpdate = () async {
        if (req.state == KeyVerificationState.askSas) await req.acceptSas();
      };
      await req.acceptVerification();
    });

    final app = await tester.setupApp(secureSetup: true);
    await tester.pumpWidget(app);
    await tester.loginAs(app, user);
    final client = app.clientManager.clients.first as MatrixClient;
    final mx = client.getMatrixClient();

    await tester.waitText("Is this you?", timeout: const Duration(seconds: 90));
    await tester.tapText("Approve from another device");
    // Our side of the emoji comparison (the existing verification page).
    try {
      await tester.waitFor(
          () =>
              find.textContaining("match").evaluate().isNotEmpty ||
              find.text("You're all set").evaluate().isNotEmpty,
          timeout: const Duration(seconds: 90));
    } catch (_) {
      tester.dumpScreen();
      rethrow;
    }
    final matches = find.textContaining("match");
    if (matches.evaluate().isNotEmpty) {
      await tester.tap(matches.first);
      await tester.pump();
    }
    await tester.waitText("You're all set",
        timeout: const Duration(seconds: 120));
    expect(mx.isUnknownSession, false, reason: "approved by the first device");

    // History comes once the first device has shared the backup key.
    String? body;
    for (var i = 0; i < 30 && body == null; i++) {
      try {
        final room = mx.getRoomById(roomId)!;
        final ev = Event.fromMatrixEvent(
            await mx.getOneRoomEvent(roomId, eventId), room);
        final d = await mx.encryption!.decryptRoomEvent(ev);
        if (d.type == EventTypes.Message) body = d.content["body"] as String?;
      } catch (_) {}
      if (body == null) await tester.run(const Duration(seconds: 2));
    }
    expect(body, "approved history");
    // After approving, this device asks the first one for the cross-signing
    // keys too (so it can approve others later). Wait for them: that's
    // part of being approved, and closing the database mid-request fails.
    var signingKeys = false;
    for (var i = 0; i < 60 && !signingKeys; i++) {
      signingKeys = await mx.encryption!.crossSigning.isCached();
      if (!signingKeys) await tester.run(const Duration(seconds: 1));
    }
    expect(signingKeys, true,
        reason: "an approved device gets the cross-signing keys");
    await app.clientManager.close();
  });

  group("set-up account (SDK level)", () {
    late App app;
    late MatrixClient client;
    late Client mx;
    late SecureSetupController ctl;
    late String userName;
    late String roomId;
    late String eventId;
    // The first recovery key. Recovery keys, not passwords, in this group:
    // it's about replacing keys, and a password-derived key takes 14-17 s
    // in a debug build here (the SDK allows 10).
    late String firstKey;

    Future<void> setUp(WidgetTester tester) async {
      userName = _uniq("sec_sdk");
      await tester.registerUser(userName);
      app = await tester.setupApp();
      await tester.pumpWidget(app);
      await tester.loginAs(app, userName);
      client = app.clientManager.clients.first as MatrixClient;
      mx = client.getMatrixClient();
      ctl = SecureSetupController(client);
      await tester.pumpUntil(SecureMessaging.load(client));
      firstKey = await tester.pumpUntil(ctl.setUpNew(replaceExisting: false));
      (roomId, eventId) =
          await tester.pumpUntil(_secretMessage(mx, "kept history"));
    }

    testWidgets("replace my recovery key: same identity, old key dead",
        (tester) async {
      await setUp(tester);
      final master = await _masterKey(mx);
      final version = await _backupVersion(mx);
      final newKey = await tester.pumpUntil(ctl.replaceKey(firstKey));
      expect(await _masterKey(mx), master, reason: "identity unchanged");
      expect(await _backupVersion(mx), version, reason: "same backup");
      expect(await ctl.checkKey(firstKey), false,
          reason: "old key stops working");
      expect(await ctl.checkKey(newKey), true);
      final raw = await tester.rawDevice(userName);
      expect(
          await tester
              .pumpUntil(_decryptOnNewDevice(raw, newKey, roomId, eventId)),
          "kept history");
      await app.clientManager.close();
    });

    testWidgets("someone used my key: new identity and backup, history kept",
        (tester) async {
      await setUp(tester);
      final master = await _masterKey(mx);
      final version = await _backupVersion(mx);
      final newKey = await tester.pumpUntil(ctl.lockOut());
      expect(await _masterKey(mx), isNot(master), reason: "new identity");
      expect(await _backupVersion(mx), isNot(version), reason: "new backup");
      expect(await ctl.checkKey(firstKey), false);
      final raw = await tester.rawDevice(userName);
      expect(
          await tester
              .pumpUntil(_decryptOnNewDevice(raw, newKey, roomId, eventId)),
          "kept history",
          reason: "this device's keys were re-uploaded to the new backup");
      await app.clientManager.close();
    });

    testWidgets("lost key, make a new one: identity changes, backup kept",
        (tester) async {
      await setUp(tester);
      final master = await _masterKey(mx);
      final version = await _backupVersion(mx);
      final newKey = await tester
          .pumpUntil(ctl.setUpNew(replaceExisting: true, keepBackup: true));
      expect(await _masterKey(mx), isNot(master));
      expect(await _backupVersion(mx), version, reason: "backup kept");
      final raw = await tester.rawDevice(userName);
      expect(
          await tester
              .pumpUntil(_decryptOnNewDevice(raw, newKey, roomId, eventId)),
          "kept history");
      await app.clientManager.close();
    });

    testWidgets("safety: nothing existing is replaced without consent",
        (tester) async {
      await setUp(tester);
      final master = await _masterKey(mx);
      final version = await _backupVersion(mx);
      final keyId = mx.encryption!.ssss.defaultKeyId;

      await expectLater(tester.pumpUntil(ctl.setUpNew(replaceExisting: false)),
          throwsA(isA<ExistingSetupException>()));
      await expectLater(
          tester.pumpUntil(ctl.replaceKey(
            "not the key",
          )),
          throwsA(isA<WrongRecoveryKeyException>()));

      expect(await _masterKey(mx), master);
      expect(await _backupVersion(mx), version);
      expect(mx.encryption!.ssss.defaultKeyId, keyId);
      expect(await ctl.checkKey(firstKey), true,
          reason: "the existing key still works");
      await app.clientManager.close();
    });
  });

  testWidgets("a cancelled password prompt changes nothing and can be retried",
      (tester) async {
    final user = _uniq("sec_cancel");
    await tester.registerUser(user);
    final app = await tester.setupApp();
    await tester.pumpWidget(app);
    await tester.loginAs(app, user);
    final client = app.clientManager.clients.first as MatrixClient;
    final mx = client.getMatrixClient();
    final ctl = SecureSetupController(client);
    await tester.pumpUntil(SecureMessaging.load(client));

    // Close the password dialog instead of answering it.
    var asked = false;
    Object? error;
    final first = ctl.setUpNew(replaceExisting: false);
    var done = false;
    first.then<void>((_) => done = true, onError: (Object e) {
      error = e;
      done = true;
    });
    final end = DateTime.now().add(const Duration(minutes: 2));
    while (!done && DateTime.now().isBefore(end)) {
      if (await tester.closePasswordDialog()) asked = true;
      await tester.pump(const Duration(milliseconds: 100));
      await Future.delayed(const Duration(milliseconds: 50));
    }
    expect(done, true, reason: "a closed dialog must not hang setup");
    if (!asked) {
      _log("the server didn't ask for the password on first upload; the "
          "cancel case can't be exercised here");
      expect(error, isNull);
    } else {
      expect(error, isNotNull);
      expect(await _masterKey(mx), isNull, reason: "nothing was uploaded");
      // An empty secret storage left behind counts as nothing: retry works.
      await tester.pumpUntil(ctl.setUpNew(replaceExisting: false));
      expect(await _masterKey(mx), isNotNull);
      expect(_secretsUnderDefaultKey(mx), true);
    }
    await app.clientManager.close();
  });
}
