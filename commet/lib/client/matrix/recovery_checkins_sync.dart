import 'dart:convert';

import 'package:commet/debug/log.dart';
import 'package:commet/ui/pages/secure_setup/secure_setup_records.dart';
import 'package:flutter/foundation.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:vodozemac/vodozemac.dart' as vod;

/// Encrypts the check-in record. The app uses the SDK's secret storage
/// helpers ([SsssCheckInCipher]); unit tests, without the native crypto
/// library, a pure-Dart copy of the same construction.
abstract class CheckInCipher {
  const CheckInCipher();
  Future<EncryptedContent> encrypt(String plain, Uint8List key, String info);

  /// Throws when [key] isn't the one it was encrypted with (bad MAC).
  Future<String> decrypt(EncryptedContent data, Uint8List key, String info);
}

/// What secret storage (SSSS) does: HKDF-SHA256 of [key] with [info] into
/// an AES key and an HMAC key, AES-256-CTR with a random IV, HMAC-SHA256
/// over the ciphertext.
class SsssCheckInCipher extends CheckInCipher {
  const SsssCheckInCipher();

  @override
  Future<EncryptedContent> encrypt(String plain, Uint8List key, String info) =>
      SSSS.encryptAes(plain, key, info);

  @override
  Future<String> decrypt(EncryptedContent data, Uint8List key, String info) =>
      SSSS.decryptAes(data, key, info);
}

/// The check-in schedule ([CheckInState]) shared by the user's Vommet
/// devices, so a check-in passed on one isn't asked again on another.
///
/// Stored in the account data event [type], encrypted on the device: the
/// server only sees an opaque blob. The key is derived (HKDF-SHA256, info
/// [info]) from the message backup's private key, which every set-up device
/// has cached; a device without it keeps using its local copy only and
/// never writes. Other Matrix apps ignore the event; older Vommet versions
/// keep their own local schedule.
///
/// Reading ([pull]) uses what sync brought, no request. Writing ([push])
/// first fetches the server's copy and merges it in, so nothing another
/// device wrote is lost, then writes only when something changed.
class RecoveryCheckInsSync {
  static const type = "im.nether.vommet.recovery_checkins";
  static const info = "im.nether.vommet.recovery_checkins.v1";
  static const algorithm = "im.nether.vommet.v1.aes-hmac-sha2";

  @visibleForTesting
  static CheckInCipher cipher = const SsssCheckInCipher();

  /// Is [key] the private key of the server's current message backup?
  /// Only asked when the server's copy doesn't open with our key, to tell
  /// "our key is old" (don't write) from "theirs is" (replace it).
  @visibleForTesting
  static Future<bool> Function(matrix.Client mx, Uint8List key)
      isCurrentBackupKey = _isCurrentBackupKey;

  /// The cached message backup key (null: this device doesn't have it).
  static Future<Uint8List?> backupKey(matrix.Client mx) async {
    final encryption = mx.encryption;
    if (encryption == null) return null;
    try {
      final secret =
          await encryption.ssss.getCached(matrix.EventTypes.MegolmBackup);
      if (secret == null) return null;
      final key = base64.decode(base64.normalize(secret));
      return key.length == 32 ? key : null;
    } catch (e) {
      Log.w("Recovery key check-ins: no usable backup key: $e");
      return null;
    }
  }

  /// The account data content for [state].
  static Future<Map<String, Object?>> seal(
      CheckInState state, Uint8List key) async {
    final e = await cipher.encrypt(jsonEncode(state.toJson()), key, info);
    return {
      "version": CheckInState.version,
      "algorithm": algorithm,
      "iv": e.iv,
      "ciphertext": e.ciphertext,
      "mac": e.mac
    };
  }

  /// The state in [content], or null: no record, one from a later version,
  /// or one that doesn't open with [key] (made with another backup key, or
  /// tampered with). Null means "absent": the local copy decides.
  static Future<CheckInState?> open(
      Map<String, Object?>? content, Uint8List key) async {
    if (content == null) return null;
    final iv = content["iv"], ciphertext = content["ciphertext"];
    final mac = content["mac"];
    if (content["algorithm"] != algorithm ||
        iv is! String ||
        ciphertext is! String ||
        mac is! String) {
      return null;
    }
    try {
      final plain = await cipher.decrypt(
          EncryptedContent(iv: iv, ciphertext: ciphertext, mac: mac),
          key,
          info);
      return CheckInState.fromJson(jsonDecode(plain));
    } catch (_) {
      return null;
    }
  }

  static Map<String, Object?>? _synced(matrix.Client mx) =>
      mx.accountData[type]?.content;

  /// Merges the copy sync brought into [records] (no request). True when
  /// that changed the local copy.
  static Future<bool> pull(matrix.Client mx, SecureSetupRecords records) async {
    final key = await backupKey(mx);
    if (key == null) return false;
    final shared = await open(_synced(mx), key);
    if (shared == null) return false;
    final changed = await records.adopt(shared);
    if (changed) {
      Log.i("Recovery key check-ins: took the schedule from another device");
    }
    return changed;
  }

  static final Map<String, Future<void>> _pushing = {};

  /// Merges the server's copy into [records] and writes the result back
  /// when it differs. Needs the backup key and the server; without either
  /// it does nothing (the local copy is kept and written next time).
  static Future<void> push(matrix.Client mx, SecureSetupRecords records) {
    final id = "${records.deviceScope}${mx.userID}";
    final previous = _pushing[id] ?? Future.value();
    final next = previous.then((_) => _push(mx, records)).catchError(
        (Object e) => Log.w("Recovery key check-ins: not shared: $e"));
    _pushing[id] = next;
    return next;
  }

  static Future<void> _push(
      matrix.Client mx, SecureSetupRecords records) async {
    final key = await backupKey(mx);
    final userId = mx.userID;
    if (key == null || userId == null) return;
    // Nothing new since the last sync: no request.
    final synced = await open(_synced(mx), key);
    if (synced != null) {
      await records.adopt(synced);
      if (records.state == synced) return;
    } else if (_synced(mx) == null && records.state.isEmpty) {
      return;
    }
    Map<String, Object?>? onServer;
    try {
      onServer = await mx.getAccountData(userId, type);
    } on matrix.MatrixException catch (e) {
      if (e.error != matrix.MatrixError.M_NOT_FOUND) rethrow;
    }
    final shared = await open(onServer, key);
    if (onServer != null && shared == null) {
      // Not ours to read: written with another backup key, or by a later
      // version. Replace it only when our key is the current one.
      if (onServer["version"] is int &&
          (onServer["version"] as int) > CheckInState.version) {
        Log.w("Recovery key check-ins: a later version's record, kept");
        return;
      }
      if (!await isCurrentBackupKey(mx, key)) {
        Log.w("Recovery key check-ins: this device's backup key is old, "
            "the shared record is left alone");
        return;
      }
      Log.i("Recovery key check-ins: the shared record was made with an "
          "older backup key; writing it again");
    }
    if (shared != null) await records.adopt(shared);
    final local = records.state;
    if (shared != null && shared == local) return;
    if (shared == null && local.isEmpty) return;
    final content = await seal(local, key);
    await mx.setAccountData(userId, type, content);
    // Don't wait for the sync echo.
    mx.accountData[type] = matrix.BasicEvent(type: type, content: content);
    Log.i("Recovery key check-ins: shared schedule written");
  }

  /// [pull] then [push]: the start of a session, after the first sync.
  static Future<void> sync(matrix.Client mx, SecureSetupRecords records) async {
    await pull(mx, records);
    await push(mx, records);
  }

  static Future<bool> _isCurrentBackupKey(
      matrix.Client mx, Uint8List key) async {
    try {
      final info = await mx.getRoomKeysVersionCurrent();
      final ours =
          vod.PkDecryption.fromSecretKey(vod.Curve25519PublicKey.fromBytes(key))
              .publicKey;
      return ours == info.authData["public_key"];
    } catch (e) {
      Log.w("Recovery key check-ins: couldn't compare the backup key: $e");
      return false;
    }
  }
}
