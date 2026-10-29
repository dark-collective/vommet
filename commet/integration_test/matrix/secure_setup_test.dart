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
import 'package:commet/client/matrix/recovery_checkins_sync.dart';
import 'package:commet/client/matrix/secure_messaging_state.dart';
import 'package:commet/client/matrix/ssss_repair.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/pages/login/login_page.dart';
import 'package:commet/ui/pages/main/main_page.dart';
import 'package:commet/ui/pages/secure_setup/login_password_memory.dart';
import 'package:commet/ui/pages/secure_setup/secure_setup_controller.dart';
import 'package:commet/ui/pages/secure_setup/secure_setup_gate.dart';
import 'package:commet/ui/pages/secure_setup/secure_setup_records.dart';
import 'package:commet/ui/pages/settings/categories/account/security/matrix/matrix_security_tab.dart';
import 'package:commet/ui/pages/settings/categories/account/security/matrix/recovery_checkins_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
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

/// The message keys are fetched from the backup in the background once
/// setup closes: wait for that before checking old messages or closing the
/// client.
Future<void> _historyImported(WidgetTester tester, App app) async {
  for (final c in app.clientManager.clients.whereType<MatrixClient>()) {
    final run = SecureSetupController.historyImportFor(c);
    if (run != null) await tester.pumpUntil(run);
  }
}

const _secretTypes = [
  EventTypes.CrossSigningMasterKey,
  EventTypes.CrossSigningSelfSigning,
  EventTypes.CrossSigningUserSigning,
  EventTypes.MegolmBackup,
];

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

/// Key ids each secret is stored under ON THE SERVER (not this device's
/// synced copy): a replaced key must be gone there too, or it still opens
/// the secrets for anyone holding it.
Future<Map<String, Set<String>>> _serverKeyIds(Client mx,
        [List<String> types = _secretTypes]) async =>
    {
      for (final type in types)
        type: ((await mx.getAccountData(mx.userID!, type))["encrypted"] as Map)
            .keys
            .cast<String>()
            .toSet(),
    };

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
    // .vommet/it/run.sh builds the native code optimised for this suite, as
    // in release builds (unoptimised, 500k PBKDF2 rounds take 11-15 s and
    // the SDK gives up after 10 s). Fail loudly instead of skipping, so the
    // real password path runs every night.
    if ((_passwordKeyMs ?? 1 << 30) > 8000) {
      fail("deriving a key from a password takes ${_passwordKeyMs} ms here, "
          "over the SDK's 10 s: is CARGO_PROFILE_DEV_OPT_LEVEL=3 set?");
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
    // Clicking Check can take the focus from the field; the test keyboard
    // then still points at the closed connection and enterText alone types
    // nowhere. Click into the field first, as a user would.
    final field = find.byType(TextField).first;
    _log("field focused after Check: "
        "${tester.state<EditableTextState>(find.descendant(of: field, matching: find.byType(EditableText))).widget.focusNode.hasFocus}");
    await tester.tap(field);
    await tester.pump();
    await tester.enterText(field, _recoveryPassword);
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
    await _historyImported(tester, app);

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
    await _historyImported(tester, app);
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
      final newKeyId = mx.encryption!.ssss.defaultKeyId;
      // Vommet issue 526: the server must not keep old-key copies.
      final onServer = await _serverKeyIds(mx);
      _log("key ids on the server after replacing: $onServer");
      expect(onServer.values, everyElement(equals({newKeyId})),
          reason: "the server holds the secrets under the new key only");
      final raw = await tester.rawDevice(userName);
      expect(
          await tester
              .pumpUntil(_decryptOnNewDevice(raw, newKey, roomId, eventId)),
          "kept history");
      await app.clientManager.close();
    });

    // Vommet issue 526: before SDK ss.20, replacing the key left every
    // secret's copy under the OLD key on the server. Rebuild that state by
    // writing old-key copies straight into the account data, then enter the
    // current key the way a user does.
    testWidgets("old-key copies left by an earlier replace are cleaned up",
        (tester) async {
      await setUp(tester);
      final ssss = mx.encryption!.ssss;
      final current = ssss.open();
      await current.unlock(recoveryKey: firstKey, postUnlock: false);
      final currentId = current.keyId;
      const theirs = "org.example.app.secret";
      await tester.pumpUntil(current.store(theirs, "another app's"));
      final old = await tester.pumpUntil(ssss.createKey());
      final oldKey = old.recoveryKey!;
      final types = [..._secretTypes, theirs];
      final secrets = <String, String>{};
      for (final type in types) {
        secrets[type] = await tester.pumpUntil(current.getStored(type));
        await tester.pumpUntil(old.store(type, secrets[type]!, add: true));
      }
      expect((await _serverKeyIds(mx, types)).values,
          everyElement(equals({currentId, old.keyId})),
          reason: "legacy state: both keys open every secret");
      expect(await ctl.checkKey(oldKey), true,
          reason: "the old key still works before the cleanup");
      expect(SsssRepair.pending(mx), 4,
          reason: "the old key opening it doesn't clean anything up");

      // The user enters their current key (unlock on this device).
      await tester.pumpUntil(ctl.unlockExisting(firstKey));

      final onServer = await _serverKeyIds(mx, types);
      _log("key ids on the server after the cleanup: $onServer");
      for (final type in _secretTypes) {
        expect(onServer[type], {currentId}, reason: type);
      }
      expect(onServer[theirs], {currentId, old.keyId},
          reason: "another app's secret is never touched");
      // Wait for this device to sync its own change.
      for (var i = 0; i < 100 && SsssRepair.pending(mx) > 0; i++) {
        await tester.run(const Duration(milliseconds: 200));
      }
      expect(SsssRepair.pending(mx), 0);
      expect(await ctl.checkKey(oldKey), false,
          reason: "the old key no longer opens the identity");
      // A fresh device: the old key opens none of the four secrets, the
      // current key still opens them all and restores the history.
      final raw = await tester.rawDevice(userName);
      final rawOld = raw.encryption!.ssss.open(old.keyId);
      await rawOld.unlock(recoveryKey: oldKey, postUnlock: false);
      for (final type in _secretTypes) {
        await expectLater(rawOld.getStored(type), throwsA(anything),
            reason: "$type no longer opens with the old key");
      }
      final rawCurrent = raw.encryption!.ssss.open(currentId);
      await rawCurrent.unlock(recoveryKey: firstKey, postUnlock: false);
      for (final type in _secretTypes) {
        expect(await rawCurrent.getStored(type), secrets[type], reason: type);
      }
      expect(
          await tester
              .pumpUntil(_decryptOnNewDevice(raw, firstKey, roomId, eventId)),
          "kept history");
      // Once done, entering the key again changes nothing.
      final before = await _serverKeyIds(mx, types);
      expect(await ctl.checkKey(firstKey), true);
      expect(await _serverKeyIds(mx, types), before);
      await _historyImported(tester, app);
      await app.clientManager.close();
    });

    // Vommet issue 526 follow-up: an account with old-key copies gets the
    // existing "Still have your recovery key?" check-in at the next launch
    // (it had none scheduled), the old key doesn't pass it, the current key
    // cleans up, and the check-in doesn't come back.
    testWidgets("old-key copies bring the recovery key check-in forward",
        (tester) async {
      await setUp(tester);
      final ssss = mx.encryption!.ssss;
      final current = ssss.open();
      await current.unlock(recoveryKey: firstKey, postUnlock: false);
      final currentId = current.keyId;
      final old = await tester.pumpUntil(ssss.createKey());
      final oldKey = old.recoveryKey!;
      for (final type in _secretTypes) {
        final secret = await tester.pumpUntil(current.getStored(type));
        await tester.pumpUntil(old.store(type, secret, add: true));
      }
      expect(SsssRepair.pending(mx), 4, reason: "legacy state");
      expect((await tester.pumpUntil(SecureMessaging.load(client))).state,
          SecureMessagingState.ready);
      final records = SecureSetupRecords(mx.userID!);
      expect(records.checkInDue(), false, reason: "no check-in scheduled");

      // Right on the main page, which has no Scaffold: the check-in's
      // "That's the one" is the dialog's own success state (it used to be a
      // snack bar, which tripped a debug assertion here).
      final mainContext = tester.element(find.byType(MainPage));

      // A launch: the sign-in gate, as the main page runs it on start.
      await preferences.experimentSecureSetup.set(true);
      Future<void> launch() =>
          SecureSetupGate.run(mainContext, app.clientManager);
      final first = launch();
      await tester.waitText("Can you still unlock your messages?");
      final field = find.byType(TextField).last;
      await tester.enterText(field, oldKey);
      await tester.tapText("Check");
      // Set up here without a method on record: the neutral wording.
      await tester.waitText("That didn't work. Check for typos, or try your "
          "recovery key if you used a phrase (or the other way round).");
      expect(SsssRepair.pending(mx), 4, reason: "the old key cleans nothing");
      await tester.tap(field); // a tap on Check unfocuses the field
      await tester.pump();
      await tester.enterText(field, firstKey);
      await tester.tapText("Check");
      await tester.waitText("That's the one. Keep it safe.");
      expect(find.text("Done"), findsOneWidget);
      expect(find.text("Can you still unlock your messages?"), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      // Closes by itself (no tap on Done).
      final shown = Stopwatch()..start();
      await tester.pumpUntil(first);
      _log("check-in success state closed itself after "
          "${shown.elapsedMilliseconds} ms");
      await tester.run(const Duration(seconds: 1));
      expect(find.text("That's the one. Keep it safe."), findsNothing);
      expect(find.byType(Dialog), findsNothing);
      expect(tester.takeException(), isNull);

      final onServer = await _serverKeyIds(mx);
      _log("key ids on the server after the check-in: $onServer");
      for (final type in _secretTypes) {
        expect(onServer[type], {currentId}, reason: type);
      }
      for (var i = 0; i < 100 && SsssRepair.pending(mx) > 0; i++) {
        await tester.run(const Duration(milliseconds: 200));
      }
      expect(SsssRepair.pending(mx), 0);

      // The next launch: no check-in, and none scheduled from now on (the
      // account had none before the cleanup).
      await tester.pumpUntil(launch());
      await tester.run(const Duration(seconds: 2));
      expect(find.text("Can you still unlock your messages?"), findsNothing);
      expect(records.repairCheckInMarked, false);
      expect(
          records.checkInDue(
              now: DateTime.now().add(const Duration(days: 400))),
          false);
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

    // Recovery key check-ins are shared by the user's Vommet devices (an
    // encrypted account data record): a check-in passed on one isn't asked
    // on another, and turning them off on one turns them off everywhere.

    /// Another Vommet device of the account, with the backup key cached
    /// (as after entering the recovery key there).
    Future<Client> otherDevice(WidgetTester tester) async {
      final raw = await tester.rawDevice(userName);
      final handle =
          raw.encryption!.ssss.open(EventTypes.CrossSigningMasterKey);
      await tester.pumpUntil(handle.unlock(keyOrPassphrase: firstKey));
      await tester.pumpUntil(handle.maybeCacheAll());
      expect(await tester.pumpUntil(RecoveryCheckInsSync.backupKey(raw)),
          isNotNull,
          reason: "the other device has the backup key");
      return raw;
    }

    /// Settings › Security, as its own page.
    void openSecurity() => unawaited(Navigator.of(navigator.currentContext!)
        .push(MaterialPageRoute(
            builder: (_) => Scaffold(
                body: ListView(children: [MatrixSecurityTab(client)])))));

    testWidgets(
        "recovery key check-ins: passed here, not due on another device",
        (tester) async {
      await setUp(tester);
      expect(
          await tester.pumpUntil(RecoveryCheckInsSync.backupKey(mx)), isNotNull,
          reason: "the app's device has the backup key");
      final records = SecureSetupRecords(mx.userID!);
      // Set up 15 days ago, the key kept in a password manager: due.
      await records.setUp(
          method: RecoveryMethod.key,
          now: DateTime.now().subtract(const Duration(days: 15)));
      expect(records.checkInDue(), true);

      final mainContext = tester.element(find.byType(MainPage));
      await preferences.experimentSecureSetup.set(true);
      final run = SecureSetupGate.run(mainContext, app.clientManager);
      await tester.waitText("Still have your recovery key?");
      await tester.enterText(find.byType(TextField).last, firstKey);
      await tester.tapText("Check");
      await tester.waitText("That's the one. Keep it safe.");
      await tester.pumpUntil(run);
      expect(records.checkInDue(), false);
      final next = records.nextCheckInAt!;
      _log("check-in passed; next around $next");
      // Shared in the background.
      for (var i = 0;
          i < 150 && mx.accountData[RecoveryCheckInsSync.type] == null;
          i++) {
        await tester.run(const Duration(milliseconds: 200));
      }
      final content = mx.accountData[RecoveryCheckInsSync.type]?.content;
      expect(content, isNotNull, reason: "the schedule was shared");
      expect(content!["algorithm"], RecoveryCheckInsSync.algorithm);
      expect(jsonEncode(content), isNot(contains("last_pass")),
          reason: "encrypted: the server sees no fields");

      // The other device: its own copy says the check-in is long overdue
      // (it never heard of this pass), until the shared copy synced in.
      final raw = await otherDevice(tester);
      final there = SecureSetupRecords(raw.userID!, deviceScope: "other");
      await there.setUp(
          method: RecoveryMethod.key,
          now: DateTime.now().subtract(const Duration(days: 40)));
      expect(there.checkInDue(), true);
      expect(raw.accountData[RecoveryCheckInsSync.type], isNotNull,
          reason: "the record came with the other device's sync");
      expect(
          await tester.pumpUntil(RecoveryCheckInsSync.pull(raw, there)), true);
      expect(there.checkInDue(), false, reason: "passed on the app's device");
      expect(there.nextCheckInAt, next);
      expect(there.checkInStreak, records.checkInStreak);
      expect(there.method, RecoveryMethod.key);

      // Settings shows that month.
      openSecurity();
      final month = DateFormat.yMMMM().format(next.toLocal());
      await tester.waitText(recoveryCheckInsNext(month));
      await app.clientManager.close();
    });

    testWidgets("recovery key check-ins: turned off on another device",
        (tester) async {
      await setUp(tester);
      final records = SecureSetupRecords(mx.userID!);
      await records.setUp(
          method: RecoveryMethod.phrase,
          now: DateTime.now().subtract(const Duration(days: 15)));
      expect(records.checkInDue(), true);

      // The other device turns check-ins off (Settings there).
      final raw = await otherDevice(tester);
      final there = SecureSetupRecords(raw.userID!, deviceScope: "other");
      await there.setCheckInsEnabled(false);
      await tester.pumpUntil(RecoveryCheckInsSync.push(raw, there));
      expect(raw.accountData[RecoveryCheckInsSync.type], isNotNull,
          reason: "written to the account");

      // Here, by sync.
      for (var i = 0;
          i < 150 && mx.accountData[RecoveryCheckInsSync.type] == null;
          i++) {
        await tester.run(const Duration(milliseconds: 200));
      }
      expect(mx.accountData[RecoveryCheckInsSync.type], isNotNull,
          reason: "synced to the app's device");

      final mainContext = tester.element(find.byType(MainPage));
      await preferences.experimentSecureSetup.set(true);
      await tester
          .pumpUntil(SecureSetupGate.run(mainContext, app.clientManager));
      await tester.run(const Duration(seconds: 2));
      expect(find.text("Still remember your recovery phrase?"), findsNothing);
      expect(find.byType(Dialog), findsNothing);
      expect(records.checkInsEnabled, false);
      expect(records.checkInDue(), false);

      openSecurity();
      await tester
          .waitText("Off. Vommet won't check that you still have your key.");
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
