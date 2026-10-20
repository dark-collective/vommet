import 'dart:async';

import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/secure_messaging_state.dart';
import 'package:commet/debug/log.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:vodozemac/vodozemac.dart' as vod;

/// The account already has secure messaging set up, so creating new keys
/// would replace them; only the explicit "start over" path may do that.
class ExistingSetupException implements Exception {
  @override
  String toString() =>
      "Secure messaging is already set up on this account. Confirm this "
      "device instead.";
}

/// The account has an older key backup (made by another app) but no
/// secret storage or cross-signing: setting up here would replace it.
class OldBackupException implements Exception {
  @override
  String toString() => "Your account has a message backup from another app";
}

/// The current backup can't be kept with a new key (this device doesn't
/// have its key, or it doesn't match). Nothing was changed.
class BackupNotKeptException implements Exception {
  @override
  String toString() => "This device can't keep your current backup";
}

/// The key, phrase or password didn't open the account's secret storage.
class WrongRecoveryKeyException implements Exception {
  @override
  String toString() => "That recovery key, phrase or password didn't work";
}

/// What was entered is shaped like a recovery key (starts with "E", 48
/// characters without spaces) but isn't a valid one: a character is missing,
/// extra or mistyped. Element and Vommet keys carry a checksum, so this is
/// caught before trying it.
class MalformedRecoveryKeyException implements Exception {
  @override
  String toString() => "That recovery key has a typo in it";
}

/// The account's identity key isn't stored in secret storage (or secret
/// storage hasn't arrived from the server yet), so no recovery key can unlock
/// it. Usually another app's "key storage" is out of sync.
class NothingToUnlockException implements Exception {
  @override
  String toString() => "Your account has nothing stored for a recovery key "
      "to unlock";
}

/// Vommet issue 129: the SDK work behind the secure messaging setup, without
/// UI. "Secret storage" (SSSS) holds the account's cross-signing keys and
/// the key-backup key, encrypted with the recovery key (or a key derived
/// from the phrase/password the user chose).
class SecureSetupController {
  SecureSetupController(this.client);

  final MatrixClient client;

  matrix.Client get mx => client.getMatrixClient();
  Encryption get _encryption => mx.encryption!;

  static bool _running = false;

  /// What exists on the account, asked fresh from the server. Throws when
  /// the server can't be asked (or answers partly), so a network problem
  /// never looks like "nothing set up".
  Future<({bool masterKey, bool secrets, bool backup})> whatExists() async {
    final uid = mx.userID!;
    final keys = await mx.queryKeys({uid: []});
    if (keys.failures?.isNotEmpty ?? false) {
      throw StateError("The server couldn't say which keys exist");
    }
    var backup = true;
    try {
      await mx.getRoomKeysVersionCurrent();
    } on matrix.MatrixException catch (e) {
      if (e.error != matrix.MatrixError.M_NOT_FOUND) rethrow;
      backup = false;
    }
    return (
      masterKey: keys.masterKeys?[uid] != null,
      secrets: SecureMessaging.secretStorageHasSecrets(mx),
      backup: backup,
    );
  }

  /// Is the cached backup key the one for the current server backup?
  Future<String?> _verifiedBackupKey() async {
    final secret =
        await _encryption.ssss.getCached(matrix.EventTypes.MegolmBackup);
    if (secret == null) return null;
    try {
      final info = await mx.getRoomKeysVersionCurrent();
      final ours = vod.PkDecryption.fromSecretKey(
              vod.Curve25519PublicKey.fromBase64(secret))
          .publicKey;
      return ours == info.authData["public_key"] ? secret : null;
    } catch (_) {
      return null;
    }
  }

  /// Create a recovery key (from [passphrase] when given), cross-signing
  /// keys and a key backup. Returns the recovery key.
  ///
  /// Unless [replaceExisting], refuses with [ExistingSetupException] when
  /// the account has a master key, real secrets or a backup (checked fresh
  /// right before), and refuses again if the SDK then asks to wipe
  /// anything. With [replaceExisting] (the user chose "start over" or "make
  /// a new key") the identity is replaced; [keepBackup] keeps the current
  /// message backup: its key, verified against the server, is stored under
  /// the new recovery key, after fetching everything from it. When that
  /// isn't possible it throws [BackupNotKeptException] before changing
  /// anything, so the user can choose to go on without it.
  Future<String> setUpNew(
      {String? passphrase,
      required bool replaceExisting,
      bool keepBackup = false}) async {
    if (_running) throw StateError("Setup is already running");
    _running = true;
    try {
      final exists = await whatExists();
      if (!replaceExisting) {
        if (exists.masterKey || exists.secrets) {
          throw ExistingSetupException();
        }
        if (exists.backup) throw OldBackupException();
      }
      String? backupKey;
      if (keepBackup && exists.backup) {
        backupKey = await _verifiedBackupKey();
        if (backupKey == null) throw BackupNotKeptException();
        await _encryption.keyManager.loadAllKeys();
      }
      return await _bootstrap(passphrase,
          replaceExisting: replaceExisting, keepBackupKey: backupKey);
    } finally {
      _running = false;
    }
  }

  Future<String> _bootstrap(String? passphrase,
      {required bool replaceExisting, String? keepBackupKey}) async {
    String? recoveryKey;
    final done = Completer<void>();
    late Bootstrap bootstrap;
    // Only an empty leftover secret storage may be replaced without consent.
    final mayReplaceStorage =
        replaceExisting || !SecureMessaging.secretStorageHasSecrets(mx);

    void fail(Object e) {
      if (!done.isCompleted) done.completeError(e);
    }

    Future<void> step(Bootstrap b) async {
      try {
        switch (b.state) {
          case BootstrapState.loading:
            return;
          case BootstrapState.askWipeSsss:
            if (!mayReplaceStorage) return fail(ExistingSetupException());
            b.wipeSsss(true);
          case BootstrapState.askUseExistingSsss:
            if (!mayReplaceStorage) return fail(ExistingSetupException());
            b.useExistingSsss(false);
          case BootstrapState.askBadSsss:
            if (!mayReplaceStorage) return fail(ExistingSetupException());
            b.ignoreBadSecrets(true);
          case BootstrapState.askUnlockSsss:
            b.unlockedSsss();
          case BootstrapState.askNewSsss:
            await b.newSsss(passphrase);
            recoveryKey = b.newSsssKey?.recoveryKey;
            if (keepBackupKey != null) {
              // Keep the backup readable with the new key, before anything
              // else changes.
              await b.newSsssKey!
                  .store(matrix.EventTypes.MegolmBackup, keepBackupKey);
            }
          case BootstrapState.openExistingSsss:
            await b.openExistingSsss();
          case BootstrapState.askWipeCrossSigning:
            // Without consent we only get here with stale secrets: the server
            // was just checked and has no master key, so nothing is lost.
            await b.wipeCrossSigning(true);
          case BootstrapState.askSetupCrossSigning:
            await b.askSetupCrossSigning(
                setupMasterKey: true,
                setupSelfSigningKey: true,
                setupUserSigningKey: true);
          case BootstrapState.askWipeOnlineKeyBackup:
            if (keepBackupKey != null) {
              // Keep the backup: check its key made it under the new key.
              if (await b.newSsssKey!
                      .getStored(matrix.EventTypes.MegolmBackup) !=
                  keepBackupKey) {
                return fail(StateError("Couldn't keep the backup key"));
              }
              b.wipeOnlineKeyBackup(false);
            } else {
              // Replacing was chosen, or (without consent) only a stale
              // secret is left: the server was just checked and has no
              // backup, so nothing is lost.
              b.wipeOnlineKeyBackup(true);
            }
          case BootstrapState.askSetupOnlineKeyBackup:
            await b.askSetupOnlineKeyBackup(true);
          case BootstrapState.error:
            fail(StateError("Secure messaging setup failed"));
          case BootstrapState.done:
            if (!done.isCompleted) done.complete();
        }
      } catch (e, s) {
        Log.onError(e, s, content: "Secure messaging setup step failed");
        fail(e);
      }
    }

    // The SDK reports the first state from Bootstrap's constructor, so
    // every state is handled exactly once through onUpdate (calling step()
    // again here raced it: two handlers on one state, "Wrong State").
    bootstrap = _encryption.bootstrap(onUpdate: (b) => step(b));
    await done.future;
    final key = recoveryKey ?? bootstrap.newSsssKey?.recoveryKey;
    if (key == null) throw StateError("No recovery key was created");
    return key;
  }

  /// "Replace my recovery key" (Vommet issue 129): same identity, a new
  /// recovery key. [currentInput] (the current key, phrase or password)
  /// unlocks the old secret storage; every secret in it (cross-signing keys,
  /// backup key) is moved under the new key ([passphrase] when given), and
  /// the old key stops working. Cross-signing keys and the backup are kept,
  /// so contacts see no change. Fails before changing anything if the
  /// current input is wrong or doesn't unlock every old key.
  Future<String> replaceKey(String currentInput, {String? passphrase}) async {
    if (_running) throw StateError("Setup is already running");
    _running = true;
    try {
      final working = await _workingInput(currentInput);
      String? recoveryKey;
      final done = Completer<void>();
      void fail(Object e) {
        if (!done.isCompleted) done.completeError(e);
      }

      Future<void> step(Bootstrap b) async {
        try {
          switch (b.state) {
            case BootstrapState.loading:
              return;
            case BootstrapState.askWipeSsss:
              b.wipeSsss(false); // keep: migrate instead
            case BootstrapState.askUseExistingSsss:
              b.useExistingSsss(false); // migrate to a new key
            case BootstrapState.askBadSsss:
              return fail(StateError("Some of your stored keys are damaged, "
                  "so they can't be moved to a new recovery key"));
            case BootstrapState.askUnlockSsss:
              for (final key in b.oldSsssKeys!.values) {
                if (key.isUnlocked) continue;
                try {
                  await key.unlock(keyOrPassphrase: working, postUnlock: false);
                } catch (_) {}
                if (!key.isUnlocked) {
                  // Its secrets would be left behind: change nothing.
                  return fail(WrongRecoveryKeyException());
                }
              }
              b.unlockedSsss();
            case BootstrapState.askNewSsss:
              await b.newSsss(passphrase);
              recoveryKey = b.newSsssKey?.recoveryKey;
            case BootstrapState.openExistingSsss:
              await b.openExistingSsss();
            case BootstrapState.askWipeCrossSigning:
              await b.wipeCrossSigning(false); // same identity
            case BootstrapState.askSetupCrossSigning:
              return fail(StateError("No identity to keep was found"));
            case BootstrapState.askWipeOnlineKeyBackup:
              b.wipeOnlineKeyBackup(false); // same backup
            case BootstrapState.askSetupOnlineKeyBackup:
              await b.askSetupOnlineKeyBackup(true);
            case BootstrapState.error:
              fail(StateError("Replacing the recovery key failed"));
            case BootstrapState.done:
              if (!done.isCompleted) done.complete();
          }
        } catch (e, s) {
          Log.onError(e, s, content: "Replacing the recovery key failed");
          fail(e);
        }
      }

      // Every state, the first one included, arrives through onUpdate.
      final bootstrap = _encryption.bootstrap(onUpdate: (b) => step(b));
      await done.future;
      final key = recoveryKey ?? bootstrap.newSsssKey?.recoveryKey;
      if (key == null) throw StateError("No recovery key was created");
      await _awaitStoredUnderOnly(bootstrap.newSsssKey!.keyId);
      return key;
    } finally {
      _running = false;
    }
  }

  /// The secrets reach this device's copy of the account data with the next
  /// sync; until then the old key still opens them here. Wait (bounded) so
  /// "the old key stops working" holds when [replaceKey] returns.
  Future<void> _awaitStoredUnderOnly(String keyId) async {
    final ssss = _encryption.ssss;
    bool done() => mx.accountData.keys
            .where((t) => mx.accountData[t]?.content['encrypted'] is Map)
            .every((t) {
          final ids = ssss.keyIdsFromType(t);
          return ids != null && ids.length == 1 && ids.first == keyId;
        });
    final until = DateTime.now().add(const Duration(seconds: 20));
    while (!done()) {
      final left = until.difference(DateTime.now());
      if (left.isNegative) {
        Log.w("Replaced recovery key: this device still sees other keys");
        return;
      }
      try {
        await mx.onSync.stream.first.timeout(left);
      } on TimeoutException {
        // Checked once more above, then logged.
      }
    }
  }

  /// "Someone may have used my key": first fetch everything from the
  /// current backup (when this device has its key), then a new recovery
  /// key, a new identity and a new backup holding every message key this
  /// device has (the SDK re-uploads them all to a new backup version).
  Future<String> lockOut({String? passphrase}) async {
    if (await _encryption.keyManager.isCached()) {
      try {
        await _encryption.keyManager.loadAllKeys();
      } catch (e, s) {
        Log.onError(e, s, content: "Loading the old backup before lock-out");
      }
    }
    return setUpNew(passphrase: passphrase, replaceExisting: true);
  }

  /// The form of [input] that opens secret storage.
  Future<String> _workingInput(String input) async =>
      (await _unlockAny(input)).candidate;

  /// Existing account: unlock secret storage with [input] (recovery key,
  /// phrase or password) and confirm this device with it. The keys to the
  /// message history are then fetched from the online backup in the
  /// background ([startHistoryImport]): on a big account that takes minutes,
  /// and the SDK already fetches a single missing key from the backup when a
  /// message can't be decrypted, so the screen doesn't wait for it.
  Future<void> unlockExisting(String input) async {
    final clock = Stopwatch()..start();
    void step(String what) => Log.i(
        "Unlock with recovery key: $what (${clock.elapsedMilliseconds} ms)");
    final handle = await _open(input);
    step("opened");
    await handle.maybeCacheAll();
    step("secrets cached");
    await _encryption.crossSigning.selfSign(openSsss: handle);
    step("device confirmed");
    startHistoryImport();
  }

  /// The background history import running per Matrix client, so only one
  /// runs at a time for an account.
  static final Expando<Future<void>> _imports = Expando("historyImport");

  /// The background history import running for [client], if any (tests
  /// wait for it before checking old messages or closing the client).
  static Future<void>? historyImportFor(MatrixClient client) =>
      _imports[client.getMatrixClient()];

  /// Fetch every message key from the online backup without waiting for it
  /// (see [loadHistoryKeys]). Does nothing while an import for this account
  /// is still running. Never throws: failures are logged.
  void startHistoryImport() {
    final m = mx;
    if (_imports[m] != null) {
      Log.i("History keys: an import is already running");
      return;
    }
    final clock = Stopwatch()..start();
    final run = loadHistoryKeys().then((_) async {
      int? count;
      try {
        // The backup's own count, from the SDK's cached backup info.
        count = (await _encryption.keyManager.getRoomKeysBackupInfo()).count;
      } catch (_) {}
      Log.i("History keys: background import finished"
          "${count == null ? "" : ", $count keys in the backup"} "
          "(${clock.elapsedMilliseconds} ms)");
    }).catchError((Object e, StackTrace s) {
      Log.onError(e, s, content: "Background history key import failed");
    });
    _imports[m] = run;
    unawaited(run.whenComplete(() => _imports[m] = null));
  }

  /// Fetch every message key from the online backup (upstream Commet never
  /// did this at sign-in, so rooms opened first stayed "Failed to decrypt").
  Future<void> loadHistoryKeys() async {
    if (mx.encryption == null || !_encryption.keyManager.enabled) return;
    try {
      await _encryption.keyManager.loadAllKeys();
    } catch (e, s) {
      Log.onError(e, s, content: "Loading message keys from backup failed");
    }
  }

  /// After approval from another device the backup key arrives as a shared
  /// secret, sometimes much later; fetch the history in the background once
  /// it's here (at once when it already is).
  void loadHistoryKeysWhenBackupKeyArrives(
      {Duration timeout = const Duration(minutes: 10)}) {
    StreamSubscription? sub;
    Timer? timer;
    var started = false;
    void stop() {
      sub?.cancel();
      timer?.cancel();
    }

    Future<void> check() async {
      try {
        if (started || !await _encryption.keyManager.isCached()) return;
        started = true;
        stop();
        startHistoryImport();
      } catch (e, s) {
        Log.onError(e, s, content: "Checking for the backup key failed");
      }
    }

    sub = _encryption.ssss.onSecretStored.stream.listen((_) => check());
    timer = Timer(timeout, stop);
    unawaited(check());
  }

  /// Does [input] open secret storage? Changes nothing.
  Future<bool> checkKey(String input) async {
    try {
      await _open(input);
      return true;
    } on WrongRecoveryKeyException {
      return false;
    } on MalformedRecoveryKeyException {
      return false;
    } on NothingToUnlockException {
      return false;
    }
  }

  Future<OpenSSSS> _open(String input) async =>
      (await _unlockAny(input)).handle;

  /// Open secret storage with [input]: every form of it (see [candidates])
  /// against every key that holds our identity, the default key first. A
  /// recovery key made after the identity was stored can sit next to the old
  /// one, and either should work. Logs why each attempt failed (never the
  /// input itself), so "didn't work" can be told apart in a log export.
  Future<({OpenSSSS handle, String candidate})> _unlockAny(String input) async {
    final ssss = _encryption.ssss;
    final type = matrix.EventTypes.CrossSigningMasterKey;
    final defaultKey = ssss.defaultKeyId;
    final keyIds = [
      ...?ssss.keyIdsFromType(type)?.where((k) => k == defaultKey),
      ...?ssss.keyIdsFromType(type)?.where((k) => k != defaultKey),
    ];
    Log.i("Unlock with recovery key: input ${describeInput(input)}; "
        "identity stored under ${keyIds.length} key(s), "
        "default ${defaultKey == null ? "none" : keyIds.contains(defaultKey) ? "among them" : "not among them"}");
    final usable = keyIds.where((k) => ssss.getKey(k) != null).toList();
    if (usable.isEmpty) {
      Log.w("Unlock with recovery key: nothing to unlock (identity stored "
          "under ${keyIds.length} key(s), "
          "${keyIds.length - usable.length} of them missing from the account)");
      throw NothingToUnlockException();
    }
    final reasons = <String>{};
    for (final keyId in usable) {
      for (final candidate in candidates(input)) {
        try {
          final handle = ssss.open(keyId);
          await handle.unlock(keyOrPassphrase: candidate, postUnlock: false);
          if (handle.isUnlocked) {
            Log.i("Unlock with recovery key: opened key "
                "${usable.indexOf(keyId) + 1} of ${usable.length}");
            return (handle: handle, candidate: candidate);
          }
        } catch (e) {
          // InvalidPassphraseException texts ("Incorrect parity", "Inalid
          // key", ...) say nothing about the input.
          reasons.add(e is InvalidPassphraseException
              ? e.cause
              : e.runtimeType.toString());
        }
      }
    }
    Log.w("Unlock with recovery key: failed against ${usable.length} key(s): "
        "${reasons.join("; ")}");
    if (looksLikeRecoveryKey(input) && !isValidRecoveryKey(input)) {
      throw MalformedRecoveryKeyException();
    }
    throw WrongRecoveryKeyException();
  }

  /// Shaped like a recovery key: "E" then letters and digits, about 48
  /// characters without spaces (Element's and ours are the same format). A
  /// look-alike typo (0 for O, l for 1) still counts, so it's reported as a
  /// typo rather than as a wrong key.
  static bool looksLikeRecoveryKey(String input) {
    final compact = input.replaceAll(RegExp(r"\s"), "");
    return compact.length >= 44 &&
        compact.length <= 52 &&
        compact.startsWith("E") &&
        RegExp(r"^[0-9A-Za-z]+$").hasMatch(compact);
  }

  /// Passes the recovery key's own checks (prefix, length, parity).
  static bool isValidRecoveryKey(String input) {
    try {
      SSSS.decodeRecoveryKey(input);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// The shape of [input] for logs, never its content.
  static String describeInput(String input) {
    final compact = input.replaceAll(RegExp(r"\s"), "");
    final kind = looksLikeRecoveryKey(input)
        ? (isValidRecoveryKey(input)
            ? "valid recovery key"
            : "recovery key with a typo")
        : "phrase/password";
    return "$kind, ${compact.length} chars without spaces"
        "${input != input.trim() ? ", surrounding whitespace" : ""}";
  }

  /// The forms worth trying for what the user typed: exactly as typed,
  /// trimmed (passwords are case-sensitive), then as a phrase (lower case,
  /// single spaces), as generated phrases are stored. A wrong form can't
  /// match by accident: the SDK checks each against the key's MAC.
  static List<String> candidates(String input) {
    final trimmed = input.trim();
    final phrase = trimmed.toLowerCase().split(RegExp(r"\s+")).join(" ");
    return {input, trimmed, phrase}.where((s) => s.isNotEmpty).toList();
  }
}
