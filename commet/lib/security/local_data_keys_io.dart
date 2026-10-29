import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:commet/config/app_config.dart';
import 'package:commet/config/preferences/preference.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart' show preferences;
import 'package:commet/security/forget_account.dart';
import 'package:commet/security/key_vault/key_vault.dart';
import 'package:commet/security/key_vault/key_hierarchy.dart';
import 'package:commet/security/key_vault/keystore_document.dart';
import 'package:commet/security/key_vault/platform_key_stores.dart';
import 'package:commet/security/local_data_keys.dart';
import 'package:commet/security/local_data_on_disk.dart';
import 'package:commet/security/local_data_setting.dart';
import 'package:commet/security/migration/database_migration.dart';
import 'package:commet/security/migration/local_data_migration.dart';
import 'package:commet/telemetry/local_data_telemetry.dart';
import 'package:commet/utils/database/encrypted_open.dart';
import 'package:path/path.dart' as p;

const bool supported = true;

/// The setting as read at start-up (or as chosen since).
LocalDataSetting _setting = LocalDataSetting.byDefault;

/// The vault is needed to open the databases: encryption is on, or a file
/// is still encrypted (turned off, not decrypted yet). Otherwise only the
/// media cache uses the key, and a locked keyring never blocks the start.
bool _needsVault = false;

/// Encrypted files are there but keystore.json isn't: no key may be made
/// (it would never open them); the start-up screen says the key is missing.
bool _keystoreGone = false;

Future<String> _keysDirectory() => PlatformKeyStores.keysDirectory();

List<String> _accounts() =>
    preferences.getRegisteredMatrixClients() ?? const <String>[];

List<String> registeredAccounts() => _accounts();

bool _isEncrypted(MigrationTarget t) =>
    EncryptedOpen.fileState(t.path) == DatabaseFileState.encrypted ||
    DatabaseMigrator.hasLeftovers(t.path);

/// How the setting file was found at start-up (telemetry, settings).
LocalDataSettingFileState _settingFile = LocalDataSettingFileState.ok;

/// The last setting write that failed, shown in the settings until one
/// works.
String? _settingWriteError;

Future<void> initLocalDataKeys(
    {required bool headless, bool deferPrompt = false}) async {
  try {
    final databaseDirectory = await AppConfig.getDatabasePath();
    final keysDirectory = p.join(databaseDirectory, "keys");
    final targets =
        LocalDataMigration.targetsIn(databaseDirectory, _accounts());
    final encrypted = targets.where(_isEncrypted).length;
    // From the disk only; a setting file that is missing or can't be read
    // keeps encryption as the disk has it (never decrypts, never forgets a
    // key because of it: LocalDataSetting.resolve).
    final (setting, fileState) =
        await LocalDataOnDisk.setting(databaseDirectory);
    _settingFile = fileState;
    if (fileState == LocalDataSettingFileState.unreadable) {
      Log.e("The local data setting file can't be read: database encryption "
          "is kept ${setting.encrypt ? "on" : "off"} as the files on disk are "
          "(nothing is decrypted or forgotten). Choose again in Settings to "
          "replace the file.");
    } else if (fileState == LocalDataSettingFileState.missing &&
        setting.encrypt &&
        !headless &&
        LocalDataOnDisk.anyEncryptedFile(databaseDirectory)) {
      // Encrypted by a build from before the setting (when it was on by
      // default), or the file was lost: it stays on rather than being
      // decrypted unasked. Written only when encrypted files are actually
      // there (never on keystore.json alone).
      try {
        await setting.write(keysDirectory);
      } on FileSystemException catch (e) {
        Log.w("Couldn't write the local data setting: ${e.runtimeType}");
      }
    }
    _setting = setting;
    _needsVault = setting.encrypt || encrypted > 0;
    _keystoreGone = KeyVault.instance == null &&
        encrypted > 0 &&
        !File(p.join(keysDirectory, "keystore.json")).existsSync();
    final vault = await PlatformKeyStores.init(
        headless: headless,
        // Opted out: the media key alone never asks for the keyring's
        // password (the key file takes over, or the media cache isn't
        // sealed for the run).
        interactive: !headless && _needsVault && !deferPrompt,
        allowCreate: !headless && !_keystoreGone);
    // The status names the store and state only, never key material.
    Log.i("Local data key: ${vault.status} (database encryption "
        "${setting.encrypt ? "on" : "off"})");
    if (!headless) unawaited(_recordState(targets, encrypted));
  } catch (e) {
    Log.w("Local data key unavailable: ${e.runtimeType}");
  }
}

Future<void> _recordState(List<MigrationTarget> targets, int encrypted) async {
  try {
    final vault = KeyVault.instance;
    final plain = targets
        .where((t) =>
            EncryptedOpen.fileState(t.path) == DatabaseFileState.plaintext)
        .length;
    final status = vault?.status;
    LocalDataTelemetry.state(
      encryptOn: _setting.encrypt,
      chosen: _setting.chosen,
      pending: _setting.encrypt
          ? (plain > 0 ? "encrypt" : "none")
          : (encrypted > 0 ? "decrypt" : "none"),
      keyStore: status != null && status.isReady
          ? (status.store?.id ?? "none")
          : "none",
      vault: _vaultStateName(status?.state),
      keyringAvailable: await vault?.keyringAvailable(),
      filesEncrypted: encrypted,
      filesPlain: plain,
      settingFile: _settingFile.name,
    );
  } catch (_) {}
}

String _vaultStateName(VaultState? state) => switch (state) {
      null => "starting",
      VaultState.noKeystore => "no_keystore",
      _ => state.name,
    };

Future<void> becomeUiEngine() async {
  final vault = KeyVault.instance;
  if (vault == null) return initLocalDataKeys(headless: false);
  if (vault.allowCreate || _keystoreGone) return;
  try {
    final status = await vault.becomeUiEngine(interactive: _needsVault);
    Log.i("Local data key: $status");
  } catch (e) {
    Log.w("Local data key unavailable: ${e.runtimeType}");
  }
}

bool settingEncrypt() => _setting.encrypt;

bool settingChosen() => _setting.chosen;

/// Saves the user's choice. Returns false when the setting couldn't be
/// written (after retries): nothing changes then, and the settings show
/// [settingWriteError].
Future<bool> choose(bool encrypt, {required String source}) async {
  final setting = LocalDataSetting(encrypt: encrypt, chosen: true);
  try {
    await setting.write(
        LocalDataSetting.debugOverride != null ? "" : await _keysDirectory());
  } catch (e) {
    Log.e("Couldn't save the local data setting: ${e.runtimeType}");
    _settingWriteError = e.runtimeType.toString();
    return false;
  }
  _setting = setting;
  _settingWriteError = null;
  _settingFile = LocalDataSettingFileState.ok;
  LocalDataTelemetry.choice(encrypt: encrypt, source: source);
  // A file that stopped being retried in the other direction starts
  // afresh.
  await resetMigrationFailures();
  final vault = KeyVault.instance;
  if (!encrypt || vault == null || !vault.status.isReady) return true;
  // Turned on with the key in the file (the keyring was locked when the
  // media key was made): the user is here now, so the keyring may ask.
  if (vault.status.store == KeyStoreKind.file &&
      !vault.pinnedToFile &&
      vault.allowCreate) {
    unawaited(() async {
      for (final store in vault.preferredStores) {
        try {
          if (await vault.moveTo(store.kind, interactive: true)) return;
        } catch (_) {}
      }
    }());
  }
  return true;
}

/// The last setting write that failed, or null.
String? settingWriteError() => _settingWriteError;

Future<LocalDataMigrationSummary?> migrateLocalData(
    {MigrationProgressCallback? onProgress, bool retryFailed = false}) async {
  final vault = KeyVault.instance;
  if (vault == null || !vault.status.isReady) return null;
  final decrypt = !_setting.encrypt;
  final migration = LocalDataMigration(
    vault: vault,
    databaseDirectory: await AppConfig.getDatabasePath(),
    accounts: _accounts()
        .where((a) => !LocalDataKeys.skippedAccounts.contains(a))
        .toList(),
    decrypt: decrypt,
    keepKeysFor: Set.of(LocalDataKeys.skippedAccounts),
  );
  if (!migration.needed && !(decrypt && vault.hasDatabaseKeys)) return null;
  final clock = Stopwatch()..start();
  final LocalDataMigrationReport? report;
  try {
    report = await migration.run(
        retryFailed: retryFailed,
        onProgress: onProgress == null
            ? null
            : (p) => onProgress(p.index, p.count, p.fraction));
  } on MigrationInterrupted {
    LocalDataTelemetry.migration(
        decrypt: decrypt, result: "interrupted", duration: clock.elapsed);
    rethrow;
  } catch (e) {
    // The app keeps working on what is still unconverted; tried again on
    // the next start.
    Log.w("Local data migration failed: ${e.runtimeType}");
    LocalDataTelemetry.migration(
        decrypt: decrypt,
        result: "failed",
        failedStep: "other",
        duration: clock.elapsed);
    return null;
  }
  if (report == null) return null;
  final done = decrypt ? report.allPlain : report.allEncrypted;
  final bytes = report.bytesToFree;
  String? noSpaceAccount;
  if (bytes != null) {
    for (final e in report.outcomes.entries) {
      if (e.value.result == MigrationResult.noSpace) {
        noSpaceAccount = e.key.account;
        if (noSpaceAccount != null) break;
      }
    }
  }
  LocalDataTelemetry.migration(
    decrypt: decrypt,
    result: done
        ? "done"
        : bytes != null
            ? "no_space"
            : report.failedStep != null || report.stoppedRetrying
                ? "failed"
                : "partial",
    failedStep: report.failedStep?.name,
    duration: clock.elapsed,
    files: report.outcomes.length,
    keysForgotten: decrypt ? report.forgotKeys : null,
  );
  if (done) return null;
  return LocalDataMigrationSummary(
      bytesToFree: bytes,
      noSpaceAccount: noSpaceAccount,
      stoppedRetrying: report.stoppedRetrying,
      decrypting: decrypt);
}

String _shortHome(String path) {
  final home =
      Platform.environment["HOME"] ?? Platform.environment["USERPROFILE"];
  if (home != null && home.isNotEmpty && p.isWithin(home, path)) {
    return p.join("~", p.relative(path, from: home));
  }
  return path;
}

LocalDataKeyPlace? _place(KeyStoreKind? kind) {
  switch (kind) {
    case null:
      return null;
    case KeyStoreKind.file:
      return LocalDataKeyPlace.file;
    case KeyStoreKind.dpapi:
      return LocalDataKeyPlace.windows;
    case KeyStoreKind.portal:
      return LocalDataKeyPlace.portal;
    case KeyStoreKind.keyring:
      if (Platform.isAndroid) return LocalDataKeyPlace.android;
      if (Platform.isIOS) return LocalDataKeyPlace.ios;
      if (Platform.isMacOS) return LocalDataKeyPlace.mac;
      return LocalDataKeyPlace.keyring;
  }
}

Future<LocalDataStartupProblem?> startupProblem() async {
  if (!_needsVault) return null;
  final folder = _shortHome(p.dirname(await AppConfig.getDatabasePath()));
  final vault = KeyVault.instance;
  final place = _place(vault?.status.store);
  LocalDataStartupProblem problem(LocalDataStartupScreen screen,
          [LocalDataMissingCause? cause]) =>
      LocalDataStartupProblem(screen,
          place: place, cause: cause, dataFolder: folder);
  if (_keystoreGone) {
    return problem(
        LocalDataStartupScreen.missing, LocalDataMissingCause.recordGone);
  }
  if (vault == null) return problem(LocalDataStartupScreen.unreachable);
  switch (vault.status.state) {
    case VaultState.ready:
      return null;
    case VaultState.locked:
      return problem(LocalDataStartupScreen.locked);
    case VaultState.missing:
      return problem(
          LocalDataStartupScreen.missing,
          vault.status.store == KeyStoreKind.file
              ? LocalDataMissingCause.fileGone
              : LocalDataMissingCause.keyringEmpty);
    case VaultState.damaged:
    case VaultState.noKeystore:
      return problem(
          LocalDataStartupScreen.missing, LocalDataMissingCause.recordGone);
    case VaultState.unavailable:
      if (vault.status.store == KeyStoreKind.file) {
        return problem(
            LocalDataStartupScreen.missing, LocalDataMissingCause.fileGone);
      }
      return problem(LocalDataStartupScreen.unreachable);
    case VaultState.busy:
    case VaultState.starting:
      return problem(LocalDataStartupScreen.unreachable);
  }
}

Future<LocalDataStartupProblem?> retryUnlock() async {
  try {
    if (_keystoreGone) {
      final keys = await _keysDirectory();
      if (File(p.join(keys, "keystore.json")).existsSync()) {
        _keystoreGone = false;
      }
    }
    final vault = KeyVault.instance;
    if (vault == null) {
      await initLocalDataKeys(headless: false);
    } else {
      await vault.unlock(interactive: true);
    }
  } catch (e) {
    Log.w("Local data key unavailable: ${e.runtimeType}");
  }
  return startupProblem();
}

const String _labelsKey = "vommet_local_data_account_labels";

Map<String, dynamic> _labels() {
  try {
    final raw = Preference.preferences?.getString(_labelsKey);
    if (raw == null) return const {};
    final json = jsonDecode(raw);
    return json is Map<String, dynamic> ? json : const {};
  } catch (_) {
    return const {};
  }
}

Future<void> rememberAccountLabels(
    Map<String, ({String? name, String? userId})> labels) async {
  final prefs = Preference.preferences;
  if (prefs == null) return;
  try {
    if (!_setting.encrypt) {
      await prefs.remove(_labelsKey);
      return;
    }
    await prefs.setString(
        _labelsKey,
        jsonEncode({
          for (final e in labels.entries)
            e.key: {"name": e.value.name, "id": e.value.userId},
        }));
  } catch (_) {}
}

Future<List<LocalDataDamagedAccount>> checkDatabases({String? only}) async {
  final vault = KeyVault.instance;
  if (vault == null || !vault.status.isReady) return const [];
  final damaged = <LocalDataDamagedAccount>[];
  final labels = _labels();
  final databaseDirectory = await AppConfig.getDatabasePath();
  final accounts = _accounts()
      .where((a) => !LocalDataKeys.skippedAccounts.contains(a))
      .where((a) => only == null || a == only)
      .toList();
  for (final t in LocalDataMigration.targetsIn(databaseDirectory, accounts)) {
    if (only != null && t.role != DatabaseRole.data) continue;
    if (EncryptedOpen.fileState(t.path) != DatabaseFileState.encrypted) {
      continue;
    }
    // Still being converted: the next start finishes it.
    if (DatabaseMigrator.hasLeftovers(t.path)) continue;
    final key = await vault.existingDatabaseKey(t.role, t.account);
    final check = key == null
        ? DatabaseOpenCheck.corrupt
        : await LocalDataOnDisk.checkOpens(t.path, key);
    if (check == DatabaseOpenCheck.ok) continue;
    // Only a damaged file (or one without a key) is deleted or set aside;
    // one that failed for another reason is kept and tried again later.
    final damagedFile = check == DatabaseOpenCheck.corrupt;
    switch (t.role) {
      case DatabaseRole.data:
        final label = labels[t.account];
        int? size;
        try {
          size = await File(t.path).length();
        } catch (_) {}
        damaged.add(LocalDataDamagedAccount(
          account: t.account!,
          filePath: _shortHome(t.path),
          size: size,
          displayName: label is Map ? label["name"] as String? : null,
          userId: label is Map ? label["id"] as String? : null,
          noKey: key == null,
          corrupt: damagedFile,
        ));
      case DatabaseRole.searchIndex:
        if (!damagedFile) {
          Log.w("An encrypted search index doesn't open right now: kept");
          continue;
        }
        // Rebuilt from the messages.
        Log.w("An encrypted search index doesn't open: deleted to rebuild");
        await DatabaseMigrator.deleteDatabaseFiles(t.path);
      case DatabaseRole.appData:
        if (!damagedFile) {
          Log.w("app_data.db doesn't open right now: kept");
          continue;
        }
        // Set aside rather than deleted; a new one is made.
        Log.w("app_data.db doesn't open with its key: set aside");
        try {
          final aside =
              "${t.path}.damaged-${DateTime.now().millisecondsSinceEpoch}";
          await File(t.path).rename(aside);
          for (final suffix in const ["-wal", "-shm"]) {
            final f = File("${t.path}$suffix");
            if (await f.exists()) await f.rename("$aside$suffix");
          }
        } catch (e) {
          Log.w("Couldn't set app_data.db aside: ${e.runtimeType}");
        }
    }
  }
  return damaged;
}

/// [name] in [parent], made unique with -2, -3 ...
String _unique(String parent, String name) {
  var candidate = p.join(parent, name);
  var n = 2;
  while (
      FileSystemEntity.typeSync(candidate) != FileSystemEntityType.notFound) {
    candidate = p.join(parent, "$name-${n++}");
  }
  return candidate;
}

Future<void> startOver({required bool keepCopy}) async {
  final databaseDirectory = await AppConfig.getDatabasePath();
  final dir = Directory(databaseDirectory);
  final setting = _setting;
  final old = KeyVault.instance;
  KeyVault.instance = null;
  try {
    await old?.dispose();
  } catch (_) {}
  if (await dir.exists()) {
    if (keepCopy) {
      final parent = LocalDataOnDisk.keptCopyParent(databaseDirectory);
      await Directory(parent).create(recursive: true);
      final target = _unique(parent, LocalDataKeys.oldFolderName());
      await dir.rename(target);
      Log.i("Start over: the old data was moved aside");
      // The copy keeps its key files (keys/ goes with it): restoring the
      // folder opens it again. Moving them out would leave them in the
      // live keys/, where a new key in a keyring would have them deleted.
    } else {
      await dir.delete(recursive: true);
      Log.i("Start over: the old data was deleted");
    }
  }
  for (final account in List<String>.from(_accounts())) {
    preferences.removeRegisteredMatrixClient(account);
  }
  await Preference.preferences?.remove(_labelsKey);
  LocalDataKeys.skippedAccounts.clear();
  _keystoreGone = false;
  try {
    await setting.write(await _keysDirectory());
  } catch (e) {
    // Read again from the disk below (nothing encrypted is left, so the
    // default applies).
    Log.e("Start over: couldn't save the encryption setting "
        "(${e.runtimeType}): the default applies");
  }
  await initLocalDataKeys(headless: false);
}

Future<void> resetAccount(String account, {required bool keepCopy}) async {
  if (account.isEmpty || p.basename(account) != account) return;
  final drift = await AppConfig.getDriftDatabasePath();
  final dir = Directory(p.join(drift, account));
  final databaseDirectory = await AppConfig.getDatabasePath();
  if (await dir.exists()) {
    try {
      if (keepCopy) {
        final kept = LocalDataOnDisk.keptCopyParent(databaseDirectory);
        await Directory(kept).create(recursive: true);
        final parent = _unique(kept, LocalDataKeys.oldFolderName());
        await Directory(parent).create(recursive: true);
        await dir.rename(p.join(parent, account));
        // The keys' salts go with the copy (and stay in keystore.json):
        // with the master key, they open it again.
        final keystore =
            File(p.join(databaseDirectory, "keys", "keystore.json"));
        if (await keystore.exists()) {
          await keystore.copy(p.join(parent, "keystore.json"));
        }
      } else {
        await dir.delete(recursive: true);
      }
    } catch (e) {
      Log.w("Couldn't remove an account's data: ${e.runtimeType}");
    }
  }
  final vault = KeyVault.instance;
  // A kept copy keeps its keys; otherwise they are forgotten.
  if (!keepCopy && vault != null && vault.status.isReady) {
    try {
      await vault.forgetAccount(account);
    } catch (_) {}
  }
  preferences.removeRegisteredMatrixClient(account);
  LocalDataKeys.skippedAccounts.remove(account);
}

Future<LocalDataPanelStatus?> panelStatus() async {
  final vault = KeyVault.instance;
  final databaseDirectory = await AppConfig.getDatabasePath();
  final accounts = _accounts();
  final targets = LocalDataMigration.targetsIn(databaseDirectory, accounts);
  bool encrypted(MigrationTarget t) =>
      EncryptedOpen.fileState(t.path) == DatabaseFileState.encrypted;
  final rows = [
    for (final account in accounts)
      LocalDataAccountRow(account,
          encrypted: targets
              .where((t) => t.account == account && t.role == DatabaseRole.data)
              .every(encrypted)),
  ];
  final appData = targets.firstWhere((t) => t.role == DatabaseRole.appData);
  String? failed;
  if (vault != null && vault.status.isReady) {
    for (final account in accounts) {
      if (vault.migrationFailures(DatabaseRole.data, account) >=
          LocalDataMigration.maxFailures) {
        failed = account;
        break;
      }
    }
  }
  final summary = LocalDataKeys.lastMigration;
  final keyringChoosable = Platform.isLinux || Platform.isWindows;
  final ready = vault != null && vault.status.isReady;
  return LocalDataPanelStatus(
    encrypt: _setting.encrypt,
    vaultReady: ready,
    accounts: rows,
    appDataEncrypted: encrypted(appData),
    place: ready ? _place(vault.status.store) : null,
    pinnedToFile: vault?.pinnedToFile ?? false,
    keyringAvailable:
        keyringChoosable && (await vault?.keyringAvailable() ?? false),
    keyringChoosable: keyringChoosable,
    bytesToFree: summary?.bytesToFree,
    noSpaceAccount: summary?.noSpaceAccount,
    failedAccount: failed,
  );
}

Future<bool> moveKey(LocalDataKeyPlace target, {bool pin = false}) async {
  final vault = KeyVault.instance;
  if (vault == null || !vault.status.isReady || !vault.allowCreate) {
    return false;
  }
  try {
    if (target == LocalDataKeyPlace.file) {
      return await vault.moveTo(KeyStoreKind.file, pin: pin);
    }
    for (final store in vault.preferredStores) {
      if (await vault.moveTo(store.kind, interactive: true)) return true;
    }
  } catch (e) {
    Log.w("Couldn't move the local data key: ${e.runtimeType}");
  }
  return false;
}

bool keyFileNoticeDue() {
  final status = KeyVault.instance?.status;
  return _setting.encrypt &&
      status != null &&
      status.isReady &&
      status.store == KeyStoreKind.file &&
      status.fileNoticeDue;
}

Future<void> acknowledgeKeyFileNotice() async {
  try {
    await KeyVault.instance?.acknowledgeFileNotice();
  } catch (_) {}
}

Future<void> resetMigrationFailures() async {
  final vault = KeyVault.instance;
  if (vault == null || !vault.status.isReady) return;
  try {
    for (final account in _accounts()) {
      await vault.setMigrationFailures(DatabaseRole.data, account, 0);
    }
  } catch (e) {
    Log.w("Couldn't reset the migration failures: ${e.runtimeType}");
  }
}

Future<void> forgetAccount(String account) async {
  try {
    await ForgetAccount.run(
        vault: KeyVault.instance,
        driftDirectory: await AppConfig.getDriftDatabasePath(),
        account: account);
  } catch (e) {
    Log.w("Couldn't forget the account's local data: ${e.runtimeType}");
  }
}
