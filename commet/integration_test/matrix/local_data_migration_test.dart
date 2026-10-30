// Local data encryption is on by default (Vommet, 2026-10-30; opt-in
// before, LOCAL-DATA-ENCRYPTION.md phase 6): a new install creates its
// databases encrypted (nothing to convert); plain SQLite left from an
// install with encryption off is converted at the next start once it is
// turned on, and turning it off decrypts them at the next start and forgets
// the database keys (the media cache's key stays).
//
// The fixture is a real account's message store: the app signs in and
// syncs a room with a message, then a copy of its data.db is registered as
// a second account name (the first one's connection stays cached on the
// database isolate, so its own file can't be converted under it). The app
// restarts: the start-up migration converts the copy, and the account comes
// back signed in with its room and message, from the converted file.

import 'dart:io';
import 'dart:typed_data';

import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/config/app_config.dart';
import 'package:commet/main.dart';
import 'package:commet/security/key_vault/key_hierarchy.dart';
import 'package:commet/security/key_vault/key_vault.dart';
import 'package:commet/security/key_vault/keystore_document.dart';
import 'package:commet/security/key_vault/platform_key_stores.dart';
import 'package:commet/security/local_data_keys.dart';
import 'package:commet/security/local_data_setting.dart';
import 'package:commet/security/migration/database_migration.dart';
import 'package:commet/security/migration/decrypted_export.dart';
import 'package:commet/ui/pages/fatal_error/fatal_error_page.dart';
import 'package:commet/utils/database/encrypted_open.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../extensions/common_flows.dart';
import '../extensions/wait_for.dart';

void _log(String s) {
  // ignore: avoid_print
  print("LDMIGRATE $s");
}

/// A signed-in account with a room and a message in its database.
typedef _Fixture = ({
  String me,
  String roomId,
  String eventId,
  String source,
  String newName,
  String fixture,
});

/// Exports the account's message store as plain SQLite as [f.newName]'s
/// and registers that name instead.
Future<void> _copyAsNewAccount(_Fixture f, String oldName) async {
  Uint8List? key;
  if (EncryptedOpen.fileState(f.source) == DatabaseFileState.encrypted) {
    key = await KeyVault.instance!
        .existingDatabaseKey(DatabaseRole.data, oldName);
    expect(key, isNotNull);
  }
  await Directory(p.dirname(f.fixture)).create(recursive: true);
  // A consistent copy (VACUUM INTO): the open store's latest writes are
  // still in its -wal file, which a plain file copy would leave behind.
  await DecryptedExport.export(f.source, key, f.fixture);
  key?.fillRange(0, key.length, 0);
  expect(EncryptedOpen.fileState(f.fixture), DatabaseFileState.plaintext);
  preferences.removeRegisteredMatrixClient(oldName);
  preferences.addRegisteredMatrixClient(f.newName);
}

Future<void> _expectAccountBack(
    WidgetTester tester, App app, _Fixture f) async {
  expect(app.clientManager.clients, hasLength(1));
  final client = app.clientManager.clients[0] as MatrixClient;
  expect(client.identifier, f.newName);
  final mx = client.getMatrixClient();
  await tester.waitFor(() => client.isLoggedIn(),
      timeout: const Duration(seconds: 30), skipPumpAndSettle: true);
  expect(mx.userID, f.me);
  final room = mx.getRoomById(f.roomId);
  expect(room, isNotNull, reason: "the room should load from the database");
  final timeline = await room!.getTimeline();
  expect(timeline.events.any((e) => e.eventId == f.eventId), isTrue,
      reason: "the message should load from the database");
  timeline.cancelSubscriptions();
  _log("account ${f.me} back with its room and message");
  try {
    await mx.leaveRoom(f.roomId);
  } catch (_) {}
}

void main() {
  testWidgets(
      "a new install is encrypted from the start; plain data is encrypted "
      "at the next start once turned on", (tester) async {
    var app = await tester.setupApp();
    await tester.pumpWidget(app);
    expect(LocalDataKeys.encrypt, isTrue, reason: "on by default");
    expect(LocalDataKeys.chosen, isFalse,
        reason: "the first-run page hasn't been answered");
    final keys = await PlatformKeyStores.keysDirectory();
    expect(LocalDataSetting.read(keys), LocalDataSetting.newInstall,
        reason: "a new install writes the default down");

    await tester.login(app);
    final oldName = app.clientManager.clients[0].identifier;
    final f = await _roomWithMessage(tester, app, "new install");
    expect(EncryptedOpen.fileState(f.source), DatabaseFileState.encrypted,
        reason: "a new install's message store is created encrypted");
    expect(DatabaseMigrator.hasLeftovers(f.source), isFalse,
        reason: "nothing was converted");
    final vault = KeyVault.instance!;
    expect(vault.status.isReady, isTrue);
    expect(
        await vault.existingDatabaseKey(DatabaseRole.data, oldName), isNotNull);

    // Plain SQLite, as an install with encryption off has it.
    await _copyAsNewAccount(f, oldName);
    await LocalDataKeys.choose(true, source: "settings");
    expect(LocalDataKeys.encrypt, isTrue);
    expect(LocalDataKeys.chosen, isTrue);

    app = await tester.restartApp();
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
    expect(find.byType(FatalErrorPage), findsNothing);

    // Converted before the database was opened.
    expect(EncryptedOpen.fileState(f.fixture), DatabaseFileState.encrypted);
    expect(DatabaseMigrator.hasLeftovers(f.fixture), isFalse);
    expect(vault.recordedState(DatabaseRole.data, f.newName),
        DatabaseEncryptionState.encrypted);
    expect(LocalDataKeys.encrypt, isTrue, reason: "the choice is kept");
    await _expectAccountBack(tester, app, f);
  });

  testWidgets(
      "turned off, the message store is decrypted at the next start and "
      "its key forgotten; the media key stays", (tester) async {
    var app = await tester.setupApp();
    await tester.pumpWidget(app);
    // The harness wipes the data folder under a running vault that still
    // holds the last test's database keys (with no setting file, new
    // databases follow those): write the setting, as an install has it.
    await LocalDataKeys.choose(false, source: "settings");
    final keys = await PlatformKeyStores.keysDirectory();
    _log("setting before login: ${LocalDataSetting.existsIn(keys)} "
        "${LocalDataSetting.read(keys)}");
    await tester.login(app);
    final oldName = app.clientManager.clients[0].identifier;
    final f = await _roomWithMessage(tester, app, "before opting out");
    // Only the fixture matters here (the copy is exported as plain SQLite
    // either way); an account store created encrypted under the wiped
    // harness is logged, not failed on.
    _log("setting after login: ${LocalDataSetting.existsIn(keys)} "
        "${LocalDataSetting.read(keys)}, source "
        "${EncryptedOpen.fileState(f.source).name}");
    await _copyAsNewAccount(f, oldName);

    // The copy as an opted-in install left it: encrypted, its key recorded.
    final vault = KeyVault.instance!;
    final key = await vault.newDatabaseKey(DatabaseRole.data, f.newName);
    final outcome = await DatabaseMigrator().migrate(f.fixture, key);
    key.fillRange(0, key.length, 0);
    expect(outcome.isEncrypted, isTrue, reason: "$outcome");
    await vault.recordState(
        DatabaseRole.data, f.newName, DatabaseEncryptionState.encrypted);
    expect(EncryptedOpen.fileState(f.fixture), DatabaseFileState.encrypted);
    final media = vault.mediaKeyStamp;
    expect(media, isNotNull);

    await LocalDataKeys.choose(false, source: "settings");
    expect(LocalDataKeys.encrypt, isFalse);
    expect(LocalDataKeys.chosen, isTrue);

    app = await tester.restartApp();
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
    expect(find.byType(FatalErrorPage), findsNothing);

    expect(EncryptedOpen.fileState(f.fixture), DatabaseFileState.plaintext);
    expect(DatabaseMigrator.hasLeftovers(f.fixture), isFalse);
    expect(
        await vault.existingDatabaseKey(DatabaseRole.data, f.newName), isNull,
        reason: "the database keys are forgotten once all is decrypted");
    expect(vault.mediaKeyStamp, media, reason: "the media cache keeps its key");
    expect(LocalDataKeys.lastMigration, isNull,
        reason: "everything should be decrypted");
    await _expectAccountBack(tester, app, f);
  });
}

/// A room with a message in the signed-in account's database.
Future<_Fixture> _roomWithMessage(
    WidgetTester tester, App app, String text) async {
  final client = app.clientManager.clients[0] as MatrixClient;
  final mx = client.getMatrixClient();
  final roomId = await mx.createRoom(name: "Local data migration fixture");
  await tester.waitFor(() => mx.getRoomById(roomId) != null,
      timeout: const Duration(seconds: 30), skipPumpAndSettle: true);
  final eventId = await mx.getRoomById(roomId)!.sendTextEvent(text);
  await tester.waitFor(
      () => mx.getRoomById(roomId)?.lastEvent?.eventId == eventId,
      timeout: const Duration(seconds: 30),
      skipPumpAndSettle: true);
  // One more sync, so the room and its message are in the database.
  await mx.onSync.stream.first.timeout(const Duration(seconds: 60));
  final drift = await AppConfig.getDriftDatabasePath();
  final newName = "ldmigrate${DateTime.now().microsecondsSinceEpoch}";
  return (
    me: mx.userID!,
    roomId: roomId,
    eventId: eventId!,
    source: p.join(drift, client.identifier, "data.db"),
    newName: newName,
    fixture: p.join(drift, newName, "data.db"),
  );
}
