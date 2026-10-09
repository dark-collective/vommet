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

    bootstrap = _encryption.bootstrap(onUpdate: (b) => step(b));
    unawaited(step(bootstrap));
    await done.future;
    final key = recoveryKey ?? bootstrap.newSsssKey?.recoveryKey;
    if (key == null) throw StateError("No recovery key was created");
    return key;
  }

  /// Existing account: unlock secret storage with [input] (recovery key,
  /// phrase or password), confirm this device with it, and fetch the keys
  /// to the message history from the online backup.
  Future<void> unlockExisting(String input) async {
    final handle = await _open(input);
    await handle.maybeCacheAll();
    await _encryption.crossSigning.selfSign(openSsss: handle);
    await loadHistoryKeys();
  }

  /// Fetch every message key from the online backup (upstream Commet never
  /// did this at sign-in, so rooms opened first stayed "Failed to decrypt").
  Future<void> loadHistoryKeys() async {
    if (!_encryption.keyManager.enabled) return;
    try {
      await _encryption.keyManager.loadAllKeys();
    } catch (e, s) {
      Log.onError(e, s, content: "Loading message keys from backup failed");
    }
  }

  /// After approval from another device the backup key arrives as a shared
  /// secret, sometimes much later; fetch the history once it's here.
  void loadHistoryKeysWhenBackupKeyArrives(
      {Duration timeout = const Duration(minutes: 10)}) {
    StreamSubscription? sub;
    Timer? timer;
    void stop() {
      sub?.cancel();
      timer?.cancel();
    }

    sub = _encryption.ssss.onSecretStored.stream.listen((_) async {
      if (await _encryption.keyManager.isCached()) {
        stop();
        await loadHistoryKeys();
      }
    });
    timer = Timer(timeout, stop);
  }

  /// Does [input] open secret storage? Changes nothing.
  Future<bool> checkKey(String input) async {
    try {
      await _open(input);
      return true;
    } on WrongRecoveryKeyException {
      return false;
    }
  }

  Future<OpenSSSS> _open(String input) async {
    for (final candidate in candidates(input)) {
      try {
        // The key that holds our identity (not just the default key).
        final handle =
            _encryption.ssss.open(matrix.EventTypes.CrossSigningMasterKey);
        await handle.unlock(keyOrPassphrase: candidate, postUnlock: false);
        if (handle.isUnlocked) return handle;
      } catch (_) {
        // try the next form
      }
    }
    throw WrongRecoveryKeyException();
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
