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
    if (!_synced(client)) {
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
      // Refresh the SDK's own copy too (for "is this device signed"). Only
      // our own list: updateUserDeviceKeys() first loads the member list of
      // every encrypted room, which took minutes on a fresh sign-in to a
      // big account.
      await mx.updateOwnDeviceKeys().timeout(timeout);
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

  /// Like [watch], and while this device is still unconfirmed, also asks
  /// the server for our own device list every [refreshEvery]: a verification
  /// started from another device (e.g. Element) ends with that device
  /// signing ours, which we'd otherwise only notice once the sync loop got
  /// round to our list.
  static Stream<SecureMessagingStatus> watchConfirmation(MatrixClient client,
      {Duration refreshEvery = const Duration(seconds: 5)}) {
    late StreamController<SecureMessagingStatus> controller;
    StreamSubscription<SecureMessagingStatus>? sub;
    Timer? timer;
    SecureMessagingStatus? last;
    var refreshing = false;

    void emit(SecureMessagingStatus status) {
      if (last != null &&
          status.state == last!.state &&
          status.hasKeyBackup == last!.hasKeyBackup) {
        return;
      }
      last = status;
      controller.add(status);
    }

    Future<void> refresh() async {
      if (refreshing || !_synced(client)) return;
      // Our list can also change outside a sync (the SDK refreshes device
      // keys in the background, after the sync that announced the change
      // was already reported): report that too, not only our own refresh.
      final now = of(client);
      if (now.state != SecureMessagingState.thisDeviceUnverified) {
        if (!controller.isClosed) emit(now);
        return;
      }
      refreshing = true;
      try {
        await client.getMatrixClient().updateOwnDeviceKeys();
        if (!controller.isClosed) emit(of(client));
      } catch (_) {
        // Next tick.
      } finally {
        refreshing = false;
      }
    }

    controller = StreamController<SecureMessagingStatus>(
      onListen: () {
        sub = watch(client).listen(emit);
        timer = Timer.periodic(refreshEvery, (_) => refresh());
      },
      onCancel: () async {
        timer?.cancel();
        await sub?.cancel();
      },
    );
    return controller.stream;
  }

  /// Our own device list, asking the server for it if the SDK doesn't have
  /// it yet (or it lacks this device, or is out of date). Null when the
  /// server couldn't be asked.
  static Future<matrix.DeviceKeysList?> ownDeviceList(matrix.Client mx) async {
    var keys = mx.userDeviceKeys[mx.userID];
    if (keys == null || keys.outdated || keys.deviceKeys[mx.deviceID] == null) {
      await mx.updateOwnDeviceKeys();
      keys = mx.userDeviceKeys[mx.userID];
    }
    return keys;
  }

  /// Our other devices that can approve this one: signed by our identity
  /// (an approval request only goes to those).
  static List<matrix.DeviceKeys> approvingDevices(
          matrix.Client mx, matrix.DeviceKeysList keys) =>
      keys.deviceKeys.values
          .where((d) =>
              d.deviceId != mx.deviceID &&
              !d.blocked &&
              d.hasValidSignatureChain(verifiedByTheirMasterKey: true))
          .toList();

  /// After this device was confirmed by another one (either side started
  /// the verification): fetch our device list with the new signature, and
  /// ask our confirmed devices for the secrets (cross-signing keys, backup
  /// key) if they haven't arrived. Safe to call more than once.
  static Future<void> finishConfirmation(matrix.Client mx) async {
    final encryption = mx.encryption;
    if (encryption == null) return;
    await mx.updateOwnDeviceKeys();
    final crossSigningCached = !encryption.crossSigning.enabled ||
        await encryption.crossSigning.isCached();
    final backupCached = !encryption.keyManager.enabled ||
        await encryption.keyManager.isCached();
    if (!crossSigningCached || !backupCached) {
      await encryption.ssss.maybeRequestAll();
    }
  }

  /// A sync has landed. [MatrixClient.firstSyncComplete] alone isn't
  /// enough: only a session started from storage sets it, so after a fresh
  /// sign-in it stayed false and every status read "unknown" until the app
  /// restarted (the setup screen and Settings › Security never saw this
  /// device being confirmed from another one).
  static bool _synced(MatrixClient client) =>
      client.firstSyncComplete || client.getMatrixClient().prevBatch != null;

  static Future<void> _firstSync(MatrixClient client) async {
    if (client.firstSyncComplete) return;
    // Started from a saved session: MatrixClient.init runs a first sync.
    final pending = client.firstSync;
    if (pending != null) return pending;
    // A fresh sign-in never goes through that (firstSync stays null, which
    // made the sign-in setup time out and close itself): wait for the
    // client's own sync loop to complete a sync instead.
    final mx = client.getMatrixClient();
    if (mx.prevBatch != null) return;
    await mx.onSync.stream.first;
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
