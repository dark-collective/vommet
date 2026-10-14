// Vommet (schema v17): once per account per session, the encryption setup
// that decides whether messages can be decrypted at all: is encryption
// enabled, are cross-signing and key backup set up and are their secrets
// cached on this device, is this device verified, how many devices the
// account has and how many are unverified or blocked, and how many rooms
// are encrypted. Yes/no answers and counts only: never keys, device IDs or
// which rooms. Most "can't decrypt" reports come down to one of these.

import 'package:commet/client/client_manager.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/telemetry/sync_stats.dart';
import 'package:commet/telemetry/telemetry.dart';

class CryptoStateTelemetry {
  static bool _done = false;

  /// Waits at most this long for an account's keys to load.
  static const _loadWait = Duration(seconds: 30);

  static Future<void> record(ClientManager manager) async {
    if (_done || !Telemetry.enabled) return;
    _done = true;
    final clients = manager.clients.whereType<MatrixClient>().toList();
    for (final (i, client) in clients.indexed) {
      try {
        await _recordAccount(client, index: i + 1, accounts: clients.length);
      } catch (_) {
        // Never let diagnostics surface as an app error.
      }
    }
  }

  static Future<void> _recordAccount(MatrixClient client,
      {required int index, required int accounts}) async {
    final mx = client.getMatrixClient();
    final enc = mx.encryption;
    bool? crossSigning, crossSigningCached, keyBackup, keyBackupCached;
    if (enc != null) {
      await mx.accountDataLoading?.timeout(_loadWait);
      await mx.userDeviceKeysLoading?.timeout(_loadWait);
      crossSigning = enc.crossSigning.enabled;
      keyBackup = enc.keyManager.enabled;
      crossSigningCached = await enc.crossSigning.isCached().timeout(_loadWait);
      keyBackupCached = await enc.keyManager.isCached().timeout(_loadWait);
    }
    final devices =
        mx.userDeviceKeys[mx.userID]?.deviceKeys.values.toList() ?? const [];
    var unverified = 0, blocked = 0;
    for (final d in devices) {
      if (d.blocked) {
        blocked++;
      } else if (!d.verified) {
        unverified++;
      }
    }
    Telemetry.record("crypto_state", {
      "account_index": index,
      "accounts": accounts,
      "own_server": SyncStats.onOwnServer(mx.userID),
      "encryption": mx.encryptionEnabled,
      "cross_signing": crossSigning,
      "cross_signing_cached": crossSigningCached,
      "key_backup": keyBackup,
      "key_backup_cached": keyBackupCached,
      if (enc != null) "own_device_verified": !mx.isUnknownSession,
      "devices": devices.length.clamp(0, 1000000),
      "unverified_devices": unverified,
      "blocked_devices": blocked,
      "rooms": mx.rooms.length.clamp(0, 1000000),
      "encrypted_rooms":
          mx.rooms.where((r) => r.encrypted).length.clamp(0, 1000000),
    });
  }
}
