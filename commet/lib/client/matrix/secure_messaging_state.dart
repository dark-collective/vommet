import 'dart:async';

import 'package:commet/client/matrix/matrix_client.dart';
import 'package:matrix/matrix.dart' as matrix;

/// Vommet: where an account stands with secure messaging (cross-signing and
/// key backup), in the words the UI uses. Shared by the sign-in setup (Vommet
/// issue 129) and the DM trust warnings (Vommet issue 130).
enum SecureMessagingState {
  /// Not loaded yet (before the first sync), or the account has no
  /// encryption support.
  unknown,

  /// The account never set up secure messaging: no recovery key, no
  /// cross-signing keys on the server.
  notSetUp,

  /// Set up on the account, but this device isn't verified yet: it can't
  /// read old messages and others see it as unconfirmed.
  thisDeviceUnverified,

  /// Set up, and this device is verified.
  ready,
}

class SecureMessagingStatus {
  const SecureMessagingStatus(this.state, {this.hasKeyBackup = false});

  final SecureMessagingState state;

  /// The account has an online key backup (message history is recoverable
  /// with the recovery key).
  final bool hasKeyBackup;

  bool get needsSetup =>
      state == SecureMessagingState.notSetUp ||
      state == SecureMessagingState.thisDeviceUnverified;

  @override
  String toString() => "$state (backup: $hasKeyBackup)";
}

class SecureMessaging {
  /// The current status, from what the client already knows (no network).
  /// Before the first sync this is [SecureMessagingState.unknown].
  static SecureMessagingStatus of(MatrixClient client) {
    if (!client.firstSyncComplete) {
      return const SecureMessagingStatus(SecureMessagingState.unknown);
    }
    return fromClient(client.getMatrixClient());
  }

  /// The decision from what [mx] has loaded (cache or sync).
  static SecureMessagingStatus fromClient(matrix.Client mx,
      {bool? serverHasMasterKey}) {
    return fromParts(
      encryption: mx.encryptionEnabled,
      hasSecretStorage: secretStorageHasSecrets(mx),
      hasMasterKey:
          serverHasMasterKey ?? mx.userDeviceKeys[mx.userID]?.masterKey != null,
      thisDeviceSigned: !mx.isUnknownSession,
      hasKeyBackup: mx.encryption?.keyManager.enabled ?? false,
    );
  }

  /// The decision on its own, for tests. "Not set up" only when there is
  /// neither a cross-signing master key on the server nor secret storage:
  /// anything that exists means an existing account, whose keys must never
  /// be replaced by mistake.
  static SecureMessagingStatus fromParts({
    required bool encryption,
    required bool hasSecretStorage,
    required bool hasMasterKey,
    required bool thisDeviceSigned,
    required bool hasKeyBackup,
  }) {
    if (!encryption) {
      return const SecureMessagingStatus(SecureMessagingState.unknown);
    }
    if (!hasMasterKey && !hasSecretStorage) {
      return SecureMessagingStatus(SecureMessagingState.notSetUp,
          hasKeyBackup: hasKeyBackup);
    }
    if (!thisDeviceSigned) {
      return SecureMessagingStatus(SecureMessagingState.thisDeviceUnverified,
          hasKeyBackup: hasKeyBackup);
    }
    return SecureMessagingStatus(SecureMessagingState.ready,
        hasKeyBackup: hasKeyBackup);
  }

  /// The status checked with the server: after the first sync, asking the
  /// server directly whether we have a cross-signing master key. If that
  /// question fails (network, server error), the answer is
  /// [SecureMessagingState.unknown], never "not set up".
  static Future<SecureMessagingStatus> load(MatrixClient client,
      {Duration timeout = const Duration(seconds: 30)}) async {
    final mx = client.getMatrixClient();
    try {
      await _firstSync(client).timeout(timeout);
      final keys = await mx.queryKeys({mx.userID!: []}).timeout(timeout);
      if (keys.failures?.isNotEmpty ?? false) {
        return const SecureMessagingStatus(SecureMessagingState.unknown);
      }
      final serverHasMasterKey = keys.masterKeys?[mx.userID] != null;
      // Refresh the SDK's own copy too (for "is this device signed").
      await mx.updateUserDeviceKeys(additionalUsers: {mx.userID!});
      return fromClient(mx, serverHasMasterKey: serverHasMasterKey);
    } catch (_) {
      return const SecureMessagingStatus(SecureMessagingState.unknown);
    }
  }

  /// Updates whenever the client syncs, de-duplicated.
  static Stream<SecureMessagingStatus> watch(MatrixClient client) async* {
    SecureMessagingStatus? last;
    var current = of(client);
    last = current;
    yield current;
    await for (final _ in client.onSync) {
      current = of(client);
      if (current.state != last?.state ||
          current.hasKeyBackup != last?.hasKeyBackup) {
        last = current;
        yield current;
      }
    }
  }

  static Future<void> _firstSync(MatrixClient client) async {
    if (client.firstSyncComplete) return;
    // MatrixClient sets firstSync when the first sync starts.
    final giveUp = DateTime.now().add(const Duration(minutes: 1));
    while (client.firstSync == null && DateTime.now().isBefore(giveUp)) {
      await Future.delayed(const Duration(milliseconds: 200));
    }
    await client.firstSync;
  }

  /// Secret storage holds a real secret under its default key (an empty
  /// key left by a cancelled setup doesn't count).
  static bool secretStorageHasSecrets(matrix.Client mx) {
    final keyId = mx.encryption?.ssss.defaultKeyId;
    if (keyId == null) return false;
    for (final type in const [
      matrix.EventTypes.CrossSigningMasterKey,
      matrix.EventTypes.CrossSigningSelfSigning,
      matrix.EventTypes.CrossSigningUserSigning,
      matrix.EventTypes.MegolmBackup,
    ]) {
      final encrypted = mx.accountData[type]?.content["encrypted"];
      if (encrypted is Map && encrypted.containsKey(keyId)) return true;
    }
    return false;
  }
}

/// For callers that only have the SDK client.
extension SecureMessagingSdk on matrix.Client {
  bool get secureMessagingSetUp =>
      SecureMessaging.secretStorageHasSecrets(this) ||
      userDeviceKeys[userID]?.masterKey != null;
}
