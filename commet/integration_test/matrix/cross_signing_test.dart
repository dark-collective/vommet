// Vommet: confirming a freshly signed-in device, against the CI homeserver.
// Every test registers its own accounts and signs in fresh.
//
// FAST tier ([registerFast], the pre-release gate via vommet_runner.dart):
// another Dart SDK device (FluffyChat's stack) approves this one, started on
// either side; a recovery key unlocks it; approving still reaches the other
// device when our own device list isn't loaded yet (the 2026-10-19 report:
// a fresh sign-in with sliding sync to an account with 117 encrypted rooms
// had no own device list for minutes, so "Approve from another device"
// failed and an approval from Element was never noticed); the sign-in setup
// still asks when the first sync takes longer than 30 s (the 2026-10-20
// report: a Pinebook Pro's first sync took minutes and nothing was asked).
//
// SLOW tier ([registerSlow], nightly via secure_setup_runner.dart): the same
// with sliding sync on, a big account, the recovery passphrase, starting
// over with a new identity, skipping and confirming later in Settings ›
// Security, and interop with matrix-js-sdk's Rust crypto (the crypto of
// Element Web/Desktop and Element X): approvals both ways and MSC4268
// shared history both ways. The js peer is .vommet/it/peers/js, found
// through IT_PEER_NODE + IT_PEER_JS (run.sh sets them up); without them
// those tests skip.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/secure_messaging_state.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/pages/login/login_page.dart';
import 'package:commet/ui/pages/matrix/verification/matrix_verification_page.dart';
import 'package:commet/ui/pages/secure_setup/secure_setup_controller.dart';
import 'package:commet/ui/pages/secure_setup/secure_setup_widgets.dart';
import 'package:commet/ui/pages/settings/categories/account/security/matrix/matrix_security_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show databaseFactoryFfi, OpenDatabaseOptions;
import 'package:vodozemac/vodozemac.dart' as vod;

import '../extensions/common_flows.dart';
import '../extensions/js_peer.dart';
import '../extensions/wait_for.dart';

const _pw = "Correct-Horse-Battery-9";
const _passphrase = "the lantern glows over the quiet harbor";
final _rng = Random();

void _log(String s) {
  // ignore: avoid_print
  print("[cross-signing-it] $s");
}

String _uniq(String prefix) =>
    "${prefix}_${DateTime.now().millisecondsSinceEpoch % 100000000}_${_rng.nextInt(9999)}";

/// The js peer (matrix-js-sdk + Rust crypto), when run.sh set it up.
final _peerNode = Platform.environment["IT_PEER_NODE"] ?? "";
final _peerScript = Platform.environment["IT_PEER_JS"] ?? "";
bool get _haveJsPeer => _peerNode.isNotEmpty && _peerScript.isNotEmpty;

/// Wall-clock time per test, printed at the end of each tier's tests.
final _timings = <String, Duration>{};

void _timed(String name, Future<void> Function(WidgetTester) body,
    {bool skip = false}) {
  testWidgets(name, skip: skip, (tester) async {
    final clock = Stopwatch()..start();
    addTearDown(() {
      _timings[name] = clock.elapsed;
      _log("TIME ${clock.elapsed.inSeconds} s: $name");
    });
    await body(tester);
  });
}

extension _Flows on WidgetTester {
  Future<String> registerUser(String name) async {
    final r =
        await http.post(Uri.https(homeserver, "/_matrix/client/v3/register"),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({
              "username": name,
              "password": _pw,
              "auth": {"type": "m.login.dummy"},
              "inhibit_login": true,
            }));
    if (r.statusCode != 200) {
      throw Exception("register $name: ${r.statusCode} ${r.body}");
    }
    return jsonDecode(r.body)["user_id"] as String;
  }

  Future<void> loginAs(App app, String user) async {
    await waitFor(() => find.byType(LoginPage).evaluate().isNotEmpty);
    final inputs = find.byType(TextField);
    await enterText(inputs.at(0), homeserver);
    await pumpAndSettle();
    await enterText(inputs.at(1), user);
    await pumpAndSettle();
    await enterText(inputs.at(2), _pw);
    await pumpAndSettle();
    await tap(find.widgetWithText(ElevatedButton, "Login"));
    await pumpAndSettle();
    await waitFor(() => app.clientManager.isLoggedIn(),
        timeout: const Duration(seconds: 20), skipPumpAndSettle: true);
  }

  Future<void> run(Duration d) async {
    final end = DateTime.now().add(d);
    while (DateTime.now().isBefore(end)) {
      await pump();
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  /// Pumps frames until [future] completes, answering the app's account
  /// password prompt like a user.
  Future<T> pumpUntil<T>(Future<T> future,
      {Duration timeout = const Duration(minutes: 2)}) async {
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
      await answerPasswordDialog();
      await pump(const Duration(milliseconds: 100));
      await Future.delayed(const Duration(milliseconds: 50));
    }
    if (error != null) Error.throwWithStackTrace(error!, trace!);
    return value as T;
  }

  Future<bool> answerPasswordDialog() async {
    if (find.text("Continue with password").evaluate().isNotEmpty) {
      await tap(find.text("Continue with password").last);
      await pump();
      return true;
    }
    final field = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == "Account Password");
    if (field.evaluate().isNotEmpty &&
        (widget<TextField>(field.last).controller?.text.isEmpty ?? true)) {
      await enterText(field.last, _pw);
      await tap(find.text("Submit").last);
      await pump();
      return true;
    }
    return false;
  }

  /// Waits for [text], answering password prompts meanwhile.
  Future<void> waitText(String text,
      {Duration timeout = const Duration(seconds: 60)}) async {
    final end = DateTime.now().add(timeout);
    while (find.text(text).evaluate().isEmpty) {
      if (DateTime.now().isAfter(end)) {
        _log("timed out waiting for \"$text\"");
        dumpScreen();
        throw TimeoutException("waitText $text");
      }
      await answerPasswordDialog();
      await pump(const Duration(milliseconds: 100));
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  /// Types into the field [finder] finds once it can be hit: enterText
  /// taps it for focus, and a page still sliding in takes no tap (the text
  /// then goes nowhere).
  Future<void> typeInto(Finder finder, String text) async {
    final target = finder.hitTestable();
    final end = DateTime.now().add(const Duration(seconds: 20));
    while (target.evaluate().isEmpty) {
      if (DateTime.now().isAfter(end)) {
        dumpScreen();
        throw TimeoutException("no field to type into");
      }
      await run(const Duration(milliseconds: 100));
    }
    await run(const Duration(milliseconds: 500)); // let the transition end
    await enterText(finder.hitTestable(), text);
    await pump();
  }

  /// Taps [text] once it can be hit: right after a page or dialog appears
  /// it's still sliding in, and a tap at its final place goes nowhere.
  Future<void> tapText(String text) async {
    final target = find.text(text).hitTestable();
    final end = DateTime.now().add(const Duration(seconds: 20));
    while (target.evaluate().isEmpty) {
      if (DateTime.now().isAfter(end)) {
        dumpScreen();
        throw TimeoutException("nothing to tap: $text");
      }
      await run(const Duration(milliseconds: 100));
    }
    await run(const Duration(milliseconds: 500)); // let the transition end
    await tap(target.last);
    await pump();
  }

  void dumpScreen() {
    final texts = <String>{
      for (final e in find.byType(Text).evaluate())
        if ((e.widget as Text).data case final String d when d.isNotEmpty) d,
    };
    _log("on screen: ${texts.take(40).join(" | ")}");
    for (final c in clientManager?.clients ?? const []) {
      if (c is! MatrixClient) continue;
      final mx = c.getMatrixClient();
      _log("client ${mx.userID} ${mx.deviceID}: "
          "unknownSession=${mx.isUnknownSession} "
          "ownList=${mx.userDeviceKeys[mx.userID]?.deviceKeys.length} "
          "status=${SecureMessaging.fromClient(mx).state}");
    }
  }

  /// Another device of [user]: a Dart SDK client with its own in-memory
  /// database that answers password prompts itself.
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
            password: _pw,
            identifier: AuthenticationUserIdentifier(user: user)));
      }
    });
    await c.checkHomeserver(Uri.https(homeserver), checkWellKnown: false);
    await c.login(LoginType.mLoginPassword,
        identifier: AuthenticationUserIdentifier(user: user),
        password: _pw,
        initialDeviceDisplayName: name);
    await c.oneShotSync();
    addTearDown(() => c.dispose(closeDatabase: true));
    return c;
  }

  /// The app with the sign-in setup on, [slidingSync] as given, signed in
  /// as [user] for the first time on this device.
  Future<(App, MatrixClient, Client)> freshSignIn(String user,
      {required bool slidingSync, bool gate = true}) async {
    final app = await setupApp(secureSetup: gate);
    await preferences.experimentSlidingSync.set(slidingSync);
    addTearDown(() => preferences.experimentSlidingSync.set(false));
    await pumpWidget(app);
    await loginAs(app, user);
    final client = app.clientManager.clients.first as MatrixClient;
    final mx = client.getMatrixClient();
    _log("signed in $user device ${mx.deviceID} slidingSync=$slidingSync");
    return (app, client, mx);
  }

  /// Our side of an emoji comparison we started: confirms the emoji.
  Future<void> confirmOurEmoji() async {
    final end = DateTime.now().add(const Duration(seconds: 90));
    while (find.text("They match!").evaluate().isEmpty &&
        find.text("You're all set").evaluate().isEmpty) {
      if (DateTime.now().isAfter(end)) {
        dumpScreen();
        throw TimeoutException("no emoji to compare");
      }
      await run(const Duration(milliseconds: 200));
    }
    if (find.text("They match!").evaluate().isNotEmpty) {
      await tap(find.text("They match!").first);
      await pump();
    }
  }

  /// A request another device sent us: the app's verification dialog.
  /// Accepts, confirms the emoji and closes it.
  Future<void> answerIncoming() async {
    final page = find.byType(MatrixVerificationPage);
    // hitTestable: the dialog slides in; a tap while it's still off-screen
    // goes nowhere.
    final accept =
        find.descendant(of: page, matching: find.text("Accept")).hitTestable();
    final end = DateTime.now().add(const Duration(seconds: 90));
    while (accept.evaluate().isEmpty) {
      if (DateTime.now().isAfter(end)) {
        dumpScreen();
        throw TimeoutException("no verification request shown");
      }
      await run(const Duration(milliseconds: 200));
    }
    await tap(accept.first);
    await pump();
    final match = find
        .descendant(of: page, matching: find.text("They match!"))
        .hitTestable();
    while (match.evaluate().isEmpty) {
      if (DateTime.now().isAfter(end)) {
        dumpScreen();
        throw TimeoutException("no emoji in the verification dialog");
      }
      await run(const Duration(milliseconds: 200));
    }
    await tap(match.first);
    await pump();
    final done = find
        .descendant(of: page, matching: find.text("Verification Complete!"))
        .hitTestable();
    while (done.evaluate().isEmpty) {
      if (DateTime.now().isAfter(end)) {
        dumpScreen();
        throw TimeoutException("verification didn't complete");
      }
      await run(const Duration(milliseconds: 200));
    }
    await tap(done.first);
    await pump();
  }

  /// Waits until this device is cross-signed and has the cross-signing and
  /// backup keys (what an approved device gets from the approving one).
  Future<void> expectConfirmed(Client mx,
      {Duration timeout = const Duration(seconds: 90)}) async {
    final end = DateTime.now().add(timeout);
    var signed = false, crossSigning = false, backup = false;
    while (true) {
      signed = !mx.isUnknownSession;
      crossSigning = await mx.encryption!.crossSigning.isCached();
      backup = await mx.encryption!.keyManager.isCached();
      if (signed && crossSigning && backup) break;
      if (DateTime.now().isAfter(end)) break;
      await run(const Duration(seconds: 1));
    }
    _log("confirmed: signed=$signed crossSigning=$crossSigning "
        "backup=$backup");
    expect(signed, true, reason: "this device is cross-signed");
    expect(crossSigning, true, reason: "it got the cross-signing keys");
    expect(backup, true, reason: "it got the backup key");
  }
}

/// A Dart SDK device that accepts every request and confirms the emoji;
/// [received] completes when a request arrives.
class _Approver {
  _Approver(this.device) {
    device.onKeyVerificationRequest.stream.listen((req) async {
      if (!received.isCompleted) received.complete(DateTime.now());
      req.onUpdate = () async {
        if (req.state == KeyVerificationState.askSas) await req.acceptSas();
        if (req.state == KeyVerificationState.done && !done.isCompleted) {
          done.complete();
        }
      };
      await req.acceptVerification();
    });
  }
  final Client device;
  final received = Completer<DateTime>();
  final done = Completer<void>();
}

/// Starts a verification of [deviceId] from [from] (another device of the
/// same account) and confirms its side of the emoji.
Future<KeyVerification> _requestFrom(Client from, String deviceId) async {
  final me = from.userID!;
  DeviceKeys? target;
  for (var i = 0; i < 60 && target == null; i++) {
    await from.updateUserDeviceKeys(additionalUsers: {me});
    target = from.userDeviceKeys[me]?.deviceKeys[deviceId];
    if (target == null) await Future.delayed(const Duration(seconds: 1));
  }
  if (target == null) throw StateError("$deviceId not in $me's device list");
  final req = await target.startVerification();
  req.onUpdate = () async {
    if (req.state == KeyVerificationState.askSas) await req.acceptSas();
  };
  return req;
}

/// [count] encrypted rooms of [owner], each joined by [members] (logged in
/// with [tokens]): what makes finding everyone we share a room with slow.
Future<void> _seedEncryptedRooms(
    Client owner, int count, Map<String, String> members) async {
  final clock = Stopwatch()..start();
  final ids = members.keys.toList();
  Future<void> one(int i) async {
    final invitees = [ids[i % ids.length], ids[(i + 1) % ids.length]].toSet();
    Future<String> create() =>
        owner.createRoom(invite: invitees.toList(), initialState: [
          StateEvent(
              type: EventTypes.Encryption,
              stateKey: "",
              content: {"algorithm": AlgorithmTypes.megolmV1AesSha2}),
        ]);
    String roomId;
    try {
      roomId = await create();
    } on MatrixException catch (e) {
      // Tuwunel now and then refuses one of 8 parallel creations ("sender's
      // membership `leave` is not `join`", CI 10-19): once more, alone.
      _log("createRoom failed, retrying: ${e.errorMessage}");
      await Future.delayed(const Duration(seconds: 1));
      roomId = await create();
    }
    for (final u in invitees) {
      final r = await http.post(
          Uri.https(_hs, "/_matrix/client/v3/join/$roomId"),
          headers: {
            "Authorization": "Bearer ${members[u]}",
            "Content-Type": "application/json"
          },
          body: "{}");
      if (r.statusCode != 200) throw Exception("join: ${r.body}");
    }
  }

  for (var i = 0; i < count; i += 8) {
    await Future.wait([for (var j = i; j < min(i + 8, count); j++) one(j)]);
  }
  _log("seeded $count encrypted rooms with ${ids.length} other users in "
      "${clock.elapsed.inSeconds} s");
}

String get _hs =>
    const String.fromEnvironment("HOMESERVER", defaultValue: "localhost");

/// Registers [count] users and returns their access tokens.
Future<Map<String, String>> _members(String prefix, int count) async {
  final out = <String, String>{};
  for (var i = 0; i < count; i++) {
    final name = _uniq("$prefix$i");
    final r = await http.post(Uri.https(_hs, "/_matrix/client/v3/register"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "username": name,
          "password": _pw,
          "auth": {"type": "m.login.dummy"},
        }));
    if (r.statusCode != 200) throw Exception("register: ${r.body}");
    final body = jsonDecode(r.body);
    out[body["user_id"] as String] = body["access_token"] as String;
  }
  return out;
}

Future<JsPeer> _jsPeer(String user, {List<String> args = const []}) {
  JsPeer.log = _log;
  final peer = JsPeer.start(
    node: _peerNode,
    script: _peerScript,
    homeserver: "https://$_hs",
    user: user,
    password: _pw,
    args: args,
    environment: {
      "NODE_EXTRA_CA_CERTS":
          "/usr/local/share/ca-certificates/vommet-it-ca.crt",
    },
  );
  return peer.then((p) {
    addTearDown(p.stop);
    return p;
  });
}

// ---------------------------------------------------------------------------
// The scenarios. Each takes the sliding sync setting, so a tier picks which.

Future<void> _approveHere(WidgetTester tester,
    {required bool slidingSync,
    int seedRooms = 0,
    bool dropOwnList = false,
    bool slowFirstSync = false}) async {
  final user = _uniq("xs_here");
  await tester.registerUser(user);
  final first = await tester.rawDevice(user, name: "First device");
  await first.initCryptoIdentity();
  if (seedRooms > 0) {
    await _seedEncryptedRooms(first, seedRooms, await _members("xs_m", 3));
  }
  final approver = _Approver(first);

  if (slowFirstSync) {
    // Longer than the 30 s the sign-in check used to allow for the first
    // sync (the 2026-10-20 report: on a Pinebook Pro the first sync took
    // minutes, the check gave up and the setup closed without asking).
    SecureMessaging.debugFirstSyncDelay = const Duration(seconds: 35);
    addTearDown(() => SecureMessaging.debugFirstSyncDelay = Duration.zero);
  }
  final (app, _, mx) = await tester.freshSignIn(user, slidingSync: slidingSync);
  await tester.waitText("Is this you?", timeout: const Duration(seconds: 120));
  SecureMessaging.debugFirstSyncDelay = Duration.zero;
  if (dropOwnList) {
    // The state from the report: no own device list yet.
    mx.userDeviceKeys.remove(mx.userID);
    _log("own device list dropped before approving");
  }
  final tapped = DateTime.now();
  await tester.tapText("Approve from another device");
  await tester.confirmOurEmoji();
  final received = await approver.received.future
      .timeout(const Duration(seconds: 60), onTimeout: () {
    tester.dumpScreen();
    throw TimeoutException("the other device never got the request");
  });
  _log("request reached the other device after "
      "${received.difference(tapped).inMilliseconds} ms");
  await tester.waitText("You're all set",
      timeout: const Duration(seconds: 120));
  await tester.expectConfirmed(mx);
  await app.clientManager.close();
}

Future<void> _approvedFromThere(WidgetTester tester,
    {required bool slidingSync}) async {
  final user = _uniq("xs_there");
  await tester.registerUser(user);
  final first = await tester.rawDevice(user, name: "First device");
  await first.initCryptoIdentity();

  final (app, _, mx) = await tester.freshSignIn(user, slidingSync: slidingSync);
  await tester.waitText("Is this you?", timeout: const Duration(seconds: 120));
  final req = await _requestFrom(first, mx.deviceID!);
  await tester.answerIncoming();
  expect(req.state, KeyVerificationState.done);
  // The setup screen notices on its own: no button pressed on it.
  await tester.waitText("You're all set",
      timeout: const Duration(seconds: 120));
  await tester.expectConfirmed(mx);
  await app.clientManager.close();
}

Future<void> _recoveryKey(WidgetTester tester,
    {required bool slidingSync, bool passphrase = false}) async {
  final user = _uniq("xs_key");
  await tester.registerUser(user);
  final first = await tester.rawDevice(user, name: "First device");
  final clock = Stopwatch()..start();
  String key;
  try {
    key = await first.initCryptoIdentity(
        passphrase: passphrase ? _passphrase : null);
  } catch (e) {
    // With a passphrase the SDK gives deriving the key 10 s (SSSS.createKey)
    // and fails the whole bootstrap past that: the same limit as below.
    if (!passphrase || clock.elapsed < const Duration(seconds: 10)) rethrow;
    _log("identity with a passphrase failed after "
        "${clock.elapsedMilliseconds} ms: $e");
    markTestSkipped("passphrase derivation takes over the SDK's 10 s here "
        "(debug build)");
    return;
  }
  _log("identity made in ${clock.elapsedMilliseconds} ms");
  if (passphrase && clock.elapsed > const Duration(seconds: 8)) {
    // The app derives the key from the passphrase again on unlock; the
    // SDK gives that 10 s, a debug build's native library can take longer.
    markTestSkipped("passphrase derivation takes ${clock.elapsed.inSeconds} "
        "s here (debug build), over the SDK's 10 s");
    return;
  }

  final (app, _, mx) = await tester.freshSignIn(user, slidingSync: slidingSync);
  await tester.waitText("Is this you?", timeout: const Duration(seconds: 120));
  await tester.tapText("Enter recovery key or phrase");
  await tester.waitText("Enter your recovery key");
  await tester.typeInto(
      find.byType(TextField).first, passphrase ? _passphrase : key);
  await tester.tapText("Unlock my messages");
  await tester.waitText("You're all set",
      timeout: const Duration(seconds: 120));
  await tester.expectConfirmed(mx);
  await _historyImported(tester, app);
  await app.clientManager.close();
}

Future<void> _startOver(WidgetTester tester) async {
  final user = _uniq("xs_reset");
  await tester.registerUser(user);
  final first = await tester.rawDevice(user, name: "Lost device");
  await first.initCryptoIdentity();
  final oldMaster = first.userDeviceKeys[first.userID]?.masterKey?.ed25519Key;

  final (app, _, mx) = await tester.freshSignIn(user, slidingSync: false);
  await tester.waitText("Is this you?", timeout: const Duration(seconds: 120));
  await tester.tapText("I've lost all my devices and my recovery key");
  await tester.waitText("Hold to start over");
  final g = await tester
      .startGesture(tester.getCenter(find.text("Hold to start over")));
  await tester.run(const Duration(milliseconds: 2600));
  await g.up();
  await tester.waitText("How do you want to save your recovery key?");
  await tester.tapText("Save in an encrypted password manager");
  await tester.tapText("Continue");
  await tester.waitText("Save it in your password manager",
      timeout: const Duration(seconds: 120));
  final key =
      tester.widget<RecoveryKeyText>(find.byType(RecoveryKeyText)).recoveryKey;
  for (final copy in [
    "I'll copy it into my password manager myself",
    "Copy it for my password manager"
  ]) {
    if (find.text(copy).evaluate().isNotEmpty) {
      await tester.tapText(copy);
      break;
    }
  }
  await tester.waitText("Let's check it saved");
  await tester.typeInto(find.byType(TextField).last, key);
  await tester.tapText("Check");
  await tester.waitText("You're all set",
      timeout: const Duration(seconds: 120));

  await mx.updateOwnDeviceKeys();
  final newMaster = mx.userDeviceKeys[mx.userID]?.masterKey?.ed25519Key;
  expect(newMaster, isNotNull);
  expect(newMaster, isNot(oldMaster), reason: "a new identity");
  await tester.expectConfirmed(mx);
  await app.clientManager.close();
}

/// Skips the sign-in setup, then confirms the device from Settings ›
/// Security: with the recovery key ([how] = "key"), with "Use another
/// device instead" ([how] = "approve"), or by accepting a request another
/// device sends while the tab is open ([how] = "incoming").
Future<void> _skipThenSettings(WidgetTester tester, String how) async {
  final user = _uniq("xs_later");
  await tester.registerUser(user);
  final first = await tester.rawDevice(user, name: "First device");
  final key = await first.initCryptoIdentity();
  final approver = how == "approve" ? _Approver(first) : null;

  final (app, client, mx) = await tester.freshSignIn(user, slidingSync: false);
  await tester.waitText("Is this you?", timeout: const Duration(seconds: 120));
  await tester.tapText("Skip for now");
  await tester.waitText("Skip secure messaging?");
  await tester.tapText("Skip anyway");
  await tester.waitText("This is for developers");
  final g =
      await tester.startGesture(tester.getCenter(find.text("Hold to skip")));
  await tester.run(const Duration(milliseconds: 2600));
  await g.up();
  await tester.run(const Duration(seconds: 2));
  expect(find.text("Is this you?"), findsNothing);
  expect(mx.isUnknownSession, true);

  // Settings › Security, as its own page.
  unawaited(Navigator.of(navigator.currentContext!).push(MaterialPageRoute(
      builder: (_) =>
          Scaffold(body: ListView(children: [MatrixSecurityTab(client)])))));
  await tester.waitText("Confirm this device");
  switch (how) {
    case "key":
      await tester.tapText("Enter recovery key");
      await tester.waitText("Enter your recovery key");
      await tester.typeInto(find.byType(TextField).first, key);
      await tester.tapText("Unlock my messages");
      await tester.waitText("You're all set",
          timeout: const Duration(seconds: 120));
      await tester.tapText("Start chatting");
    case "approve":
      await tester.tapText("Use another device instead");
      await tester.confirmOurEmoji();
      await approver!.received.future.timeout(const Duration(seconds: 60));
      await tester.waitText("You're all set",
          timeout: const Duration(seconds: 120));
      await tester.tapText("Start chatting");
    case "incoming":
      final req = await _requestFrom(first, mx.deviceID!);
      await tester.answerIncoming();
      expect(req.state, KeyVerificationState.done);
  }
  // The tab notices without being reopened.
  final end = DateTime.now().add(const Duration(seconds: 60));
  while (find.text("Confirm this device").evaluate().isNotEmpty) {
    if (DateTime.now().isAfter(end)) {
      tester.dumpScreen();
      fail("Settings › Security still asks to confirm this device");
    }
    await tester.run(const Duration(milliseconds: 500));
  }
  await tester.expectConfirmed(mx);
  await _historyImported(tester, app);
  await app.clientManager.close();
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

// js peer (matrix-js-sdk + Rust crypto): approvals --------------------------

Future<void> _jsApprovesHere(WidgetTester tester) async {
  final user = _uniq("xs_jsa");
  await tester.registerUser(user);
  final peer = await _jsPeer(user, args: ["--create-identity", "--accept"]);
  await peer.next("waiting");

  final (app, _, mx) = await tester.freshSignIn(user, slidingSync: false);
  await tester.waitText("Is this you?", timeout: const Duration(seconds: 120));
  await tester.tapText("Approve from another device");
  await tester.confirmOurEmoji();
  final got = await peer.next("request_received");
  expect(got["from_device"], mx.deviceID);
  await peer.next("done");
  await tester.waitText("You're all set",
      timeout: const Duration(seconds: 120));
  await tester.expectConfirmed(mx);
  await app.clientManager.close();
}

Future<void> _jsApprovesFromThere(WidgetTester tester) async {
  final user = _uniq("xs_jsb");
  await tester.registerUser(user);
  final peer = await _jsPeer(user, args: ["--create-identity"]);
  await peer.next("identity");

  final (app, _, mx) = await tester.freshSignIn(user, slidingSync: false);
  await tester.waitText("Is this you?", timeout: const Duration(seconds: 120));
  await peer.command({"cmd": "verify", "device": mx.deviceID}, "request_sent");
  await tester.answerIncoming();
  await peer.next("done");
  await tester.waitText("You're all set",
      timeout: const Duration(seconds: 120));
  await tester.expectConfirmed(mx);
  await app.clientManager.close();
}

// js peer: MSC4268 shared history --------------------------------------------

/// Signed in (no setup screen) with a cross-signing identity unless
/// [identity] is off.
Future<(App, Client)> _historyUser(WidgetTester tester, String user,
    {bool identity = true}) async {
  final (app, _, mx) =
      await tester.freshSignIn(user, slidingSync: false, gate: false);
  if (identity) await tester.pumpUntil(mx.initCryptoIdentity());
  return (app, mx);
}

Future<String> _decrypt(Client mx, String roomId, String eventId) async {
  final room = mx.getRoomById(roomId)!;
  try {
    final ev =
        Event.fromMatrixEvent(await mx.getOneRoomEvent(roomId, eventId), room);
    final d = await mx.encryption!.decryptRoomEvent(ev);
    return d.type == EventTypes.Message ? "body:${d.content["body"]}" : "utd";
  } on DecryptException catch (e) {
    return "utd:${e.cause}";
  } on MatrixException catch (e) {
    return "not_visible:${e.errcode}";
  } catch (e) {
    return "utd:$e";
  }
}

/// The js peer invites us to a room whose history is shared.
/// [withheld]: one message from before the history was shared, which the
/// bundle must list as m.history_not_shared. [trusted]: the peer has a
/// cross-signing identity (otherwise we must not take its bundle).
Future<void> _peerSharesHistory(WidgetTester tester,
    {bool withheld = false, bool trusted = true}) async {
  final me = _uniq("xs_hin");
  final meId = await tester.registerUser(me);
  final them = _uniq("xs_hpeer");
  await tester.registerUser(them);
  final (app, mx) = await _historyUser(tester, me);
  final peer = await _jsPeer(them, args: [if (trusted) "--create-identity"]);
  if (trusted) await peer.next("identity");

  final room = (await peer.command(
      {"cmd": "create_room", "visibility": withheld ? "joined" : "shared"},
      "room"))["room_id"] as String;
  Map<String, Object?>? hidden;
  if (withheld) {
    hidden = await peer
        .command({"cmd": "send", "room": room, "body": "hidden"}, "sent");
    await peer.command(
        {"cmd": "set_visibility", "room": room, "visibility": "shared"}, "ok");
  }
  final before = (await peer.command(
      {"cmd": "send", "room": room, "body": "before the invite"},
      "sent"))["event_id"] as String;
  await peer.command({"cmd": "invite", "room": room, "user": meId}, "ok");

  await tester.waitFor(
      () => mx.getRoomById(room)?.membership == Membership.invite,
      timeout: const Duration(seconds: 60),
      skipPumpAndSettle: true);
  await tester.pumpUntil(mx.joinRoom(room));
  var body = "";
  for (var i = 0; i < 30; i++) {
    body = await tester.pumpUntil(_decrypt(mx, room, before));
    if (body.startsWith("body:") || !trusted && i >= 10) break;
    await tester.run(const Duration(seconds: 1));
  }
  final imported = await mx.encryption!.historySharing.importedHistory(room);
  _log("peer -> us: $body, imported $imported");
  if (!trusted) {
    expect(body, isNot(startsWith("body:")),
        reason: "history from an inviter without a cross-signed device");
    expect(imported, isNull);
  } else {
    expect(body, "body:before the invite");
    expect(imported?.sender, isNotNull);
  }
  if (hidden != null) {
    await mx.encryption!.historySharing.loadWithheld(room);
    expect(
        mx.encryption!.historySharing
            .isHistoryNotShared(room, hidden["session_id"] as String),
        true,
        reason: "the bundle said this session wasn't shared");
    expect(await _decrypt(mx, room, hidden["event_id"] as String),
        isNot(startsWith("body:")));
  }
  await app.clientManager.close();
}

/// We invite the js peer to our room whose history is shared.
/// [withheld]: one message sent before the room's state was loaded, so
/// its session isn't flagged shareable (the bundle withholds it).
/// [trusted]: we have a cross-signing identity.
/// [memberFirst]: the peer joins before we send, so it gets the key as a
/// room member (the 2026-10-19 break: keys carrying the shared_history flag
/// under more than one name were dropped by Element's crypto).
Future<void> _weShareHistory(WidgetTester tester,
    {bool withheld = false,
    bool trusted = true,
    bool memberFirst = false}) async {
  final me = _uniq("xs_hout");
  await tester.registerUser(me);
  final them = _uniq("xs_hpeer");
  final themId = await tester.registerUser(them);
  final (app, mx) = await _historyUser(tester, me, identity: trusted);
  final peer = await _jsPeer(them, args: ["--create-identity"]);
  await peer.next("identity");

  // Withheld: the room starts members-only; what we send then must not be
  // in the bundle (the SDK starts a new session when it becomes shared).
  final room = await tester.pumpUntil(mx.createRoom(initialState: [
    StateEvent(
        type: EventTypes.Encryption,
        stateKey: "",
        content: {"algorithm": AlgorithmTypes.megolmV1AesSha2}),
    StateEvent(
        type: EventTypes.HistoryVisibility,
        stateKey: "",
        content: {"history_visibility": withheld ? "joined" : "shared"}),
  ]));
  await tester.waitFor(() => mx.getRoomById(room)?.encrypted == true,
      timeout: const Duration(seconds: 30), skipPumpAndSettle: true);
  final r = mx.getRoomById(room)!;
  await tester.pumpUntil(r.postLoad()); // opening the room does this
  String? hiddenSession;
  if (withheld) {
    final hidden = (await tester.pumpUntil(r.sendTextEvent("hidden")))!;
    hiddenSession = await _sessionOf(tester, mx, room, hidden);
    await tester.pumpUntil(r.setHistoryVisibility(HistoryVisibility.shared));
    await tester.waitFor(() => r.historyVisibility == HistoryVisibility.shared,
        timeout: const Duration(seconds: 30), skipPumpAndSettle: true);
  }
  if (memberFirst) {
    await tester.pumpUntil(mx.inviteUser(room, themId));
    await peer.command({"cmd": "join", "room": room}, "joined");
    await tester.waitFor(() => r.getParticipants().length >= 2,
        timeout: const Duration(seconds: 30), skipPumpAndSettle: true);
  }
  final before =
      (await tester.pumpUntil(r.sendTextEvent("before the invite")))!;
  if (!memberFirst) {
    await tester.pumpUntil(mx.inviteUser(room, themId));
    await peer.command({"cmd": "join", "room": room}, "joined");
  }
  final read = await peer.command({
    "cmd": "read",
    "room": room,
    "event_ids": [before],
    "retries": trusted ? 20 : 10,
  }, "messages");
  final events = (read["events"] as List).cast<Map>();
  _log("us -> peer: $events");
  if (trusted) {
    expect(events[0]["body"], "before the invite",
        reason: "Element's crypto takes our history bundle");
  } else {
    expect(events[0]["body"], isNull,
        reason: "no history from a device without cross-signing");
  }
  if (hiddenSession != null) {
    // The server doesn't show the peer what was sent while the room was
    // members-only anyway, so look at the keys it got instead.
    final keys =
        await peer.command({"cmd": "room_keys", "room": room}, "room_keys");
    final ids = (keys["session_ids"] as List).cast<String>();
    _log("peer's sessions for the room: $ids; withheld $hiddenSession");
    expect(ids, contains(await _sessionOf(tester, mx, room, before)),
        reason: "the shared session is in the bundle");
    expect(ids, isNot(contains(hiddenSession)),
        reason: "the members-only session stays withheld");
  }
  await app.clientManager.close();
}

/// Vommet issue 436: two copies of one megolm session, the creator's room
/// key (flagged shareable, from a later message index) and a copy from
/// message 0 without the flag (a forwarded key, whose flag we drop, or a
/// key backup copy). In either order, the stored session must keep both the
/// earliest index and the flag, or our invite bundles withhold the session
/// (before the fix the earlier copy replaced the flagged one).
Future<void> _flagSurvivesEarlierCopy(WidgetTester tester) async {
  final me = _uniq("xs_hflag");
  await tester.registerUser(me);
  final (app, mx) = await _historyUser(tester, me, identity: false);
  final keyManager = mx.encryption!.keyManager;
  final roomId = "!${_uniq("i436")}:${tester.homeserver}";
  String key32() =>
      base64Encode(List<int>.generate(32, (_) => _rng.nextInt(256)))
          .replaceAll("=", "");

  for (final forwardFirst in [false, true]) {
    final out = vod.GroupSession();
    final fromStart = vod.InboundGroupSession(out.sessionKey).exportAt(0)!;
    for (var i = 0; i < 3; i++) {
      out.encrypt("message $i");
    }
    final sessionId = out.sessionId;
    final senderKey = key32();
    final claimed = {"ed25519": key32()};
    Future<void> roomKey() => keyManager.setInboundGroupSession(
        roomId,
        sessionId,
        senderKey,
        {
          "algorithm": AlgorithmTypes.megolmV1AesSha2,
          "room_id": roomId,
          "session_id": sessionId,
          "session_key": out.sessionKey,
          "org.matrix.msc3061.shared_history": true,
        },
        senderClaimedKeys: claimed);
    Future<void> earlierCopy() => keyManager.setInboundGroupSession(
        roomId,
        sessionId,
        senderKey,
        {
          "algorithm": AlgorithmTypes.megolmV1AesSha2,
          "room_id": roomId,
          "session_id": sessionId,
          "session_key": fromStart,
          "forwarding_curve25519_key_chain": [key32()],
        },
        forwarded: true,
        senderClaimedKeys: claimed);
    if (forwardFirst) {
      await tester.pumpUntil(earlierCopy());
      await tester.pumpUntil(roomKey());
    } else {
      await tester.pumpUntil(roomKey());
      await tester.pumpUntil(earlierCopy());
    }
    // From the database, as an invite bundle reads it.
    keyManager.clearInboundGroupSessions();
    final stored = await tester
        .pumpUntil(keyManager.loadInboundGroupSession(roomId, sessionId));
    _log("forwardFirst=$forwardFirst: first index "
        "${stored?.inboundGroupSession?.firstKnownIndex}, "
        "shared ${stored?.sharedHistory}");
    expect(stored?.inboundGroupSession?.firstKnownIndex, 0,
        reason: "the copy from message 0 is kept (forwardFirst=$forwardFirst)");
    expect(stored?.sharedHistory, isTrue,
        reason: "the creator's shared_history flag is kept "
            "(forwardFirst=$forwardFirst)");
  }
  await app.clientManager.close();
}

/// Vommet issue 439: a session we sent with before Vommet set the
/// shared_history mark (simulated by removing it from the stored copy)
/// joins the bundle when we invite someone: the room's history was shared
/// the whole time, by its history visibility events on the server. With
/// "Let people who join later read my messages" off it stays withheld.
Future<void> _ownOlderKeysShared(WidgetTester tester,
    {required bool settingOff}) async {
  final me = _uniq("xs_hown");
  await tester.registerUser(me);
  final themId = await tester.registerUser(_uniq("xs_hinv"));
  final (app, mx) = await _historyUser(tester, me, identity: false);
  final room = await tester.pumpUntil(mx.createRoom(initialState: [
    StateEvent(
        type: EventTypes.Encryption,
        stateKey: "",
        content: {"algorithm": AlgorithmTypes.megolmV1AesSha2}),
    StateEvent(
        type: EventTypes.HistoryVisibility,
        stateKey: "",
        content: {"history_visibility": "shared"}),
  ]));
  await tester.waitFor(() => mx.getRoomById(room)?.encrypted == true,
      timeout: const Duration(seconds: 30), skipPumpAndSettle: true);
  final r = mx.getRoomById(room)!;
  await tester.pumpUntil(r.postLoad());
  final sent = (await tester.pumpUntil(r.sendTextEvent("before the mark")))!;
  final sessionId = await _sessionOf(tester, mx, room, sent);

  // Make it look like a session from before the mark.
  final stored = (await tester
      .pumpUntil(mx.database.getInboundGroupSession(room, sessionId)))!;
  final content = (jsonDecode(stored.content) as Map<String, dynamic>)
    ..removeWhere((k, _) => k.endsWith("shared_history"));
  await tester.pumpUntil(mx.database.storeInboundGroupSession(
      room,
      sessionId,
      stored.pickle,
      jsonEncode(content),
      stored.indexes,
      stored.allowedAtIndex,
      stored.senderKey,
      stored.senderClaimedKeys));
  final keyManager = mx.encryption!.keyManager;
  keyManager.clearInboundGroupSessions();
  final sharing = mx.encryption!.historySharing;
  Future<Set<String>> bundled() async =>
      (await tester.pumpUntil(sharing.buildBundle(room)))["room_keys"]!
          .map((k) => k["session_id"] as String)
          .toSet();
  expect(await bundled(), isNot(contains(sessionId)),
      reason: "the unmarked session starts out withheld");

  if (settingOff) {
    await tester.pumpUntil(sharing.setSharingAllowed(false));
    await tester.waitFor(() => !sharing.userAllowsSharing(r),
        timeout: const Duration(seconds: 30), skipPumpAndSettle: true);
  }
  final report = sharing.onReport.stream
      .firstWhere((e) => e.direction == "send")
      .timeout(const Duration(seconds: 60));
  await tester.pumpUntil(mx.inviteUser(room, themId));
  final outcome = await tester.pumpUntil(report);
  _log("invite outcome ${outcome.outcome}, ${outcome.keys} keys, "
      "${outcome.withheld} withheld (settingOff=$settingOff)");

  keyManager.clearInboundGroupSessions();
  final after = await tester
      .pumpUntil(keyManager.loadInboundGroupSession(room, sessionId));
  if (settingOff) {
    expect(after?.sharedHistory, isFalse,
        reason: "no mark while the setting is off");
    expect(await bundled(), isNot(contains(sessionId)));
  } else {
    expect(after?.sharedHistory, isTrue,
        reason: "our own session from a shared period gets the mark");
    expect(await bundled(), contains(sessionId),
        reason: "the invite bundle now carries our older message");
  }
  await app.clientManager.close();
}

/// The megolm session [eventId] (ours, encrypted) was sent with.
Future<String> _sessionOf(
    WidgetTester tester, Client mx, String roomId, String eventId) async {
  final ev = await tester.pumpUntil(mx.getOneRoomEvent(roomId, eventId));
  return ev.content["session_id"] as String;
}

// ---------------------------------------------------------------------------

/// The pre-release gate's share: Dart peers, no sliding sync except for the
/// regression it was reported with.
void registerFast() {
  _timed("cross-signing fast: approve here, the other device gets it",
      (t) => _approveHere(t, slidingSync: false));
  _timed("cross-signing fast: approval started on the other device",
      (t) => _approvedFromThere(t, slidingSync: false));
  _timed("cross-signing fast: recovery key",
      (t) => _recoveryKey(t, slidingSync: false));
  _timed(
      "cross-signing fast: own device list missing, sliding sync, 20 rooms",
      (t) =>
          _approveHere(t, slidingSync: true, seedRooms: 20, dropOwnList: true));
  _timed("cross-signing fast: a slow first sync still asks at sign-in",
      (t) => _approveHere(t, slidingSync: false, slowFirstSync: true));
  _timed("MSC4268: an earlier copy of a key keeps its shared_history flag",
      _flagSurvivesEarlierCopy);
  _timed("MSC4268: our own older keys join the invite bundle",
      (t) => _ownOlderKeysShared(t, settingOff: false));
  _timed("MSC4268: no mark on our older keys with the setting off",
      (t) => _ownOlderKeysShared(t, settingOff: true));
  tearDownAll(() => _log("TIMINGS fast: $_timings"));
}

/// Nightly only.
void registerSlow() {
  _timed("cross-signing slow: approve here, sliding sync",
      (t) => _approveHere(t, slidingSync: true));
  _timed("cross-signing slow: approval from the other device, sliding sync",
      (t) => _approvedFromThere(t, slidingSync: true));
  _timed("cross-signing slow: recovery key, sliding sync",
      (t) => _recoveryKey(t, slidingSync: true));
  _timed("cross-signing slow: recovery passphrase",
      (t) => _recoveryKey(t, slidingSync: false, passphrase: true));
  _timed("cross-signing slow: own device list missing, no sliding sync",
      (t) => _approveHere(t, slidingSync: false, dropOwnList: true));
  _timed("cross-signing slow: big account (120 encrypted rooms), sliding sync",
      (t) => _approveHere(t, slidingSync: true, seedRooms: 120));
  _timed(
      "cross-signing slow: big account (120 encrypted rooms), no sliding sync",
      (t) => _approveHere(t, slidingSync: false, seedRooms: 120));
  _timed("cross-signing slow: lost everything, start over", _startOver);
  _timed("cross-signing slow: skipped, then recovery key in Settings",
      (t) => _skipThenSettings(t, "key"));
  _timed("cross-signing slow: skipped, then another device from Settings",
      (t) => _skipThenSettings(t, "approve"));
  _timed(
      "cross-signing slow: skipped, approved from the other device "
      "while Settings is open",
      (t) => _skipThenSettings(t, "incoming"));

  final noPeer = !_haveJsPeer;
  _timed("interop (matrix-js-sdk rust crypto): we ask, it approves",
      _jsApprovesHere,
      skip: noPeer);
  _timed("interop (matrix-js-sdk rust crypto): it starts, we accept",
      _jsApprovesFromThere,
      skip: noPeer);
  _timed("interop MSC4268: peer invites us, we read its history",
      (t) => _peerSharesHistory(t),
      skip: noPeer);
  _timed("interop MSC4268: we invite the peer, it reads our history",
      (t) => _weShareHistory(t),
      skip: noPeer);
  _timed(
      "interop: a member on Element's crypto reads what we send in a "
      "shared-history room",
      (t) => _weShareHistory(t, memberFirst: true),
      skip: noPeer);
  _timed("interop MSC4268: peer's unshared history stays withheld",
      (t) => _peerSharesHistory(t, withheld: true),
      skip: noPeer);
  _timed("interop MSC4268: our unshared history stays withheld",
      (t) => _weShareHistory(t, withheld: true),
      skip: noPeer);
  _timed("interop MSC4268: no history from a peer without cross-signing",
      (t) => _peerSharesHistory(t, trusted: false),
      skip: noPeer);
  _timed(
      "interop MSC4268: the peer takes no history from us without "
      "cross-signing",
      (t) => _weShareHistory(t, trusted: false),
      skip: noPeer);
  tearDownAll(() => _log("TIMINGS slow: $_timings"));
}

void main() {
  registerFast();
  registerSlow();
}
