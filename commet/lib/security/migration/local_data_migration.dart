// Vommet: local data encryption, the one-time migration of an install's
// plaintext databases (LOCAL-DATA-ENCRYPTION.md §6). The UI engine runs it
// at start-up, after the key vault is ready and before the database server
// opens anything; the splash shows its progress.
//
// Order: app_data.db (small), then each account's data.db, then its
// search_index.db. What happens when a file can't be encrypted:
// - app_data.db (an index of the media cache) and search_index.db (derived
//   from the messages) are deleted, securely, and made again encrypted when
//   the file itself is damaged (or its key is wrong), or after failing
//   [LocalDataMigration.maxFailures] times; otherwise kept and retried;
// - data.db stays plaintext and keeps working; a failure is retried on the
//   next starts, at most [LocalDataMigration.maxFailures] times, then only
//   when the user asks; not enough space is retried on every start and
//   reported ("Free up …").
//
// The same runs backwards when the user turns local data encryption off
// (decrypt: true): encrypted files are decrypted with the same safety; a
// derived file that can't be is deleted (made again plaintext), data.db
// stays encrypted and keeps working until a later start manages it. Once
// nothing encrypted is left, the database keys are forgotten (the media key
// stays: the media cache is always encrypted), except those of accounts left
// out of the run (Continue without) or still encrypted: they are decrypted
// on a later start.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:commet/debug/log.dart';
import 'package:commet/security/database_in_use.dart';
import 'package:commet/security/key_vault/key_hierarchy.dart';
import 'package:commet/security/key_vault/key_vault.dart';
import 'package:commet/security/key_vault/keystore_document.dart';
import 'package:commet/security/migration/database_migration.dart';
import 'package:commet/utils/database/encrypted_open.dart';
import 'package:path/path.dart' as p;

class MigrationTarget {
  const MigrationTarget(this.path, this.role, this.account);
  final String path;
  final DatabaseRole role;
  final String? account;

  @override
  String toString() =>
      "${role.fileName}${account != null ? " ($account)" : ""}";
}

class MigrationProgress {
  const MigrationProgress(this.index, this.count, this.fraction);

  /// 1-based number of the file being encrypted, of [count].
  final int index;
  final int count;

  /// 0..1 of that file.
  final double fraction;
}

class LocalDataMigrationReport {
  final Map<MigrationTarget, MigrationOutcome> outcomes = {};

  /// Files left alone this run (opened by another engine, or failed too
  /// often).
  final List<MigrationTarget> skipped = [];

  /// The most a file still needs freed to be encrypted, or null.
  int? get bytesToFree {
    int? most;
    for (final o in outcomes.values) {
      if (o.result != MigrationResult.noSpace) continue;
      final need = (o.bytesNeeded ?? 0) - (o.bytesFree ?? 0);
      if (need > 0 && (most == null || need > most)) most = need;
    }
    return most;
  }

  /// A message store stopped being retried after failing again and again.
  bool stoppedRetrying = false;

  /// Decrypting: everything was plaintext at the end and the database keys
  /// were forgotten.
  bool forgotKeys = false;

  /// The first step that failed, for telemetry.
  MigrationStep? get failedStep {
    for (final o in outcomes.values) {
      if (o.result == MigrationResult.failed && o.step != null) return o.step;
    }
    return null;
  }

  bool get allEncrypted =>
      skipped.isEmpty &&
      outcomes.values
          .every((o) => o.isEncrypted || o.result == MigrationResult.missing);

  bool get allPlain =>
      skipped.isEmpty &&
      outcomes.values
          .every((o) => o.isPlain || o.result == MigrationResult.missing);
}

class LocalDataMigration {
  LocalDataMigration({
    required this.vault,
    required this.databaseDirectory,
    required this.accounts,
    DatabaseMigrator? migrator,
    this.inUse = DatabaseInUse.isInUse,
    this.decrypt = false,
    this.keepKeysFor = const {},
  }) : migrator = migrator ?? DatabaseMigrator();

  static const int maxFailures = 3;

  /// A lock older than this was left by a run that died (a live run touches
  /// it every [_heartbeat]).
  static const Duration staleLock = Duration(minutes: 2);
  static const Duration _heartbeat = Duration(seconds: 20);

  final KeyVault vault;

  /// The app's database directory (AppConfig.getDatabasePath).
  final String databaseDirectory;

  /// The registered accounts (client names).
  final List<String> accounts;

  final DatabaseMigrator migrator;
  final bool Function(String path) inUse;

  /// Decrypts instead (local data encryption turned off).
  final bool decrypt;

  /// Accounts left out of this run (Continue without): their database keys
  /// are kept when decrypting, for a later start to decrypt them.
  final Set<String> keepKeysFor;

  /// The accounts whose keys are still needed: [keepKeysFor] and those with
  /// a file still encrypted (or being converted).
  Set<String> _keysStillNeeded() => {
        ...keepKeysFor,
        for (final t in targets)
          if (t.account != null &&
              (EncryptedOpen.fileState(t.path) == DatabaseFileState.encrypted ||
                  DatabaseMigrator.hasLeftovers(t.path)))
            t.account!,
      };

  DatabaseFileState get _from =>
      decrypt ? DatabaseFileState.encrypted : DatabaseFileState.plaintext;

  String get _lockPath => p.join(vault.keystoreFile.directory, ".migrate.lock");

  List<MigrationTarget> get targets => targetsIn(databaseDirectory, accounts);

  /// The app's database files under [databaseDirectory]: app_data.db and
  /// each of [accounts]' message store and search index.
  static List<MigrationTarget> targetsIn(
      String databaseDirectory, List<String> accounts) {
    final drift = p.join(databaseDirectory, "account", "drift");
    return [
      MigrationTarget(p.join(databaseDirectory, "app", "app_data.db"),
          DatabaseRole.appData, null),
      for (final account in accounts)
        MigrationTarget(
            p.join(drift, account, "data.db"), DatabaseRole.data, account),
      for (final account in accounts)
        MigrationTarget(p.join(drift, account, "search_index.db"),
            DatabaseRole.searchIndex, account),
    ];
  }

  /// Whether a file still needs encrypting, or a run was interrupted. Cheap
  /// (reads headers only); when false the splash shows nothing about it.
  bool get needed => targets.any((t) =>
      EncryptedOpen.fileState(t.path) == _from ||
      DatabaseMigrator.hasLeftovers(t.path));

  /// Encrypts what is still plaintext. Returns null when it didn't run (the
  /// vault isn't ready, or another engine is migrating). [retryFailed]
  /// tries a message store again that failed too often (Try again).
  Future<LocalDataMigrationReport?> run(
      {void Function(MigrationProgress progress)? onProgress,
      bool retryFailed = false}) async {
    if (!vault.status.isReady || !vault.allowCreate) return null;
    if (decrypt && !needed) {
      // Nothing (left) to decrypt: still forget keys a killed run kept.
      final keep = _keysStillNeeded();
      if (vault.hasDatabaseKeysExcept(keep)) {
        await vault.forgetDatabaseKeys(keep: keep);
        return LocalDataMigrationReport()..forgotKeys = keep.isEmpty;
      }
    }
    final lock = await _takeLock();
    if (lock == null) {
      Log.i("Local data migration: another engine is running it");
      return null;
    }
    final heartbeat = Timer.periodic(_heartbeat, (_) {
      try {
        lock.setLastModifiedSync(DateTime.now());
      } catch (_) {}
    });
    try {
      await vault.refresh();
      final report = LocalDataMigrationReport();
      final todo = targets
          .where((t) =>
              EncryptedOpen.fileState(t.path) == _from ||
              DatabaseMigrator.hasLeftovers(t.path))
          .toList();
      for (var i = 0; i < todo.length; i++) {
        final target = todo[i];
        void progress(double f) =>
            onProgress?.call(MigrationProgress(i + 1, todo.length, f));
        progress(0);
        await _migrateOne(target, report, retryFailed, progress);
      }
      // A derived file that failed was deleted: nothing encrypted left.
      if (decrypt && report.skipped.isEmpty && !needed) {
        final keep = _keysStillNeeded();
        if (vault.hasDatabaseKeysExcept(keep)) {
          await vault.forgetDatabaseKeys(keep: keep);
        }
        report.forgotKeys = keep.isEmpty;
        Log.i(keep.isEmpty
            ? "Local data migration: everything is plaintext; database keys "
                "forgotten"
            : "Local data migration: done; the keys of ${keep.length} "
                "account(s) left out are kept");
      }
      return report;
    } finally {
      heartbeat.cancel();
      try {
        await lock.delete();
      } catch (_) {}
    }
  }

  Future<void> _migrateOne(MigrationTarget t, LocalDataMigrationReport report,
      bool retryFailed, void Function(double) onProgress) async {
    final plaintext = EncryptedOpen.fileState(t.path) == _from;
    if (plaintext &&
        t.role == DatabaseRole.data &&
        !retryFailed &&
        vault.migrationFailures(t.role, t.account) >= maxFailures) {
      report.skipped.add(t);
      report.stoppedRetrying = true;
      // Leftovers of an interrupted run are still cleaned up.
      await migrator.resume(t.path);
      return;
    }

    final Uint8List key;
    try {
      final found = decrypt
          ? await vault.existingDatabaseKey(t.role, t.account)
          : await vault.newDatabaseKey(t.role, t.account);
      if (found == null) {
        // Encrypted, but its salt isn't known: it can't be opened anyway.
        Log.w("Local data migration: no key recorded for $t");
        final outcome = const MigrationOutcome(MigrationResult.failed,
            detail: "no key recorded", corrupt: true);
        report.outcomes[t] = outcome;
        await _settle(t, outcome);
        return;
      }
      key = found;
    } on VaultNotReady catch (e) {
      Log.w("Local data migration: no key for $t (${e.status.state.name})");
      report.skipped.add(t);
      return;
    }

    try {
      if (plaintext) {
        await vault.recordState(
            t.role, t.account, DatabaseEncryptionState.migrating);
        // After "migrating" is recorded (see DatabaseInUse).
        if (inUse(t.path)) {
          Log.i("Local data migration: $t is open in another engine; "
              "next start");
          await vault.recordState(t.role, t.account, _fromState);
          report.skipped.add(t);
          return;
        }
      }

      final outcome = decrypt
          ? await migrator.decrypt(t.path, key, onProgress: onProgress)
          : await migrator.migrate(t.path, key, onProgress: onProgress);
      report.outcomes[t] = outcome;
      Log.i("Local data migration: $t → $outcome");
      await _settle(t, outcome);
    } on MigrationInterrupted {
      rethrow;
    } on Exception catch (e) {
      // Not a migration outcome (keystore.json, the file system): the
      // plaintext is kept, the state set back.
      Log.w("Local data migration: $t failed: ${e.runtimeType}");
      report.outcomes[t] = MigrationOutcome(MigrationResult.failed,
          detail: e.runtimeType.toString());
      await _settle(t, report.outcomes[t]!);
    } finally {
      key.fillRange(0, key.length, 0);
    }
  }

  Future<void> _settle(MigrationTarget t, MigrationOutcome outcome) async {
    Future<void> state(DatabaseEncryptionState s) async {
      try {
        await vault.recordState(t.role, t.account, s);
      } catch (_) {}
    }

    switch (outcome.result) {
      case MigrationResult.encrypted:
      case MigrationResult.alreadyEncrypted:
        await state(DatabaseEncryptionState.encrypted);
        await _failures(t, 0);
      case MigrationResult.decrypted:
      case MigrationResult.alreadyPlain:
        await state(DatabaseEncryptionState.plain);
        await _failures(t, 0);
      case MigrationResult.missing:
        break;
      case MigrationResult.noSpace:
      case MigrationResult.failed:
        // Only a real failure counts: running out of disk may pass, and
        // never makes derived data be deleted.
        final failures = vault.migrationFailures(t.role, t.account) + 1;
        if (t.role != DatabaseRole.data &&
            (outcome.corrupt ||
                (outcome.result == MigrationResult.failed &&
                    failures >= maxFailures))) {
          // Derived data that is damaged (or keeps failing): made again
          // (encrypted or not, as the setting says) when it is next
          // opened. A failure that may pass keeps it, to try again.
          await _deleteDatabase(t.path);
          await state(DatabaseEncryptionState.plain);
          await _failures(t, 0);
          return;
        }
        await state(_fromState);
        if (outcome.result == MigrationResult.failed) {
          await _failures(t, failures);
        }
    }
  }

  DatabaseEncryptionState get _fromState => decrypt
      ? DatabaseEncryptionState.encrypted
      : DatabaseEncryptionState.plain;

  Future<void> _failures(MigrationTarget t, int count) async {
    try {
      await vault.setMigrationFailures(t.role, t.account, count);
    } catch (_) {}
  }

  static Future<void> _deleteDatabase(String path) async {
    await DatabaseMigrator.secureDelete(path);
    for (final suffix in const ["-wal", "-shm", "-journal"]) {
      await DatabaseMigrator.secureDelete("$path$suffix");
    }
  }

  /// keys/.migrate.lock, created exclusively; null when another live run
  /// holds it.
  Future<File?> _takeLock() async {
    await vault.keystoreFile.ensureDirectory();
    final lock = File(_lockPath);
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        await lock.create(exclusive: true);
        return lock;
      } on FileSystemException {
        try {
          final stat = await lock.stat();
          if (stat.type != FileSystemEntityType.notFound &&
              DateTime.now().difference(stat.modified) < staleLock) {
            return null;
          }
          await lock.delete();
        } catch (_) {}
      }
    }
    return null;
  }
}
