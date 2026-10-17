// Vommet: export this account's message keys to a key file, and import a key
// file from Vommet or another Matrix app (Element, Cinny, ...).
import 'package:commet/client/matrix/key_export/megolm_key_file.dart';
import 'package:commet/debug/log.dart';
import 'package:matrix/encryption/utils/session_key.dart';
import 'package:matrix/matrix.dart';

class KeyImportResult {
  const KeyImportResult(
      {required this.imported,
      required this.alreadyHad,
      required this.invalid});

  /// Keys this device didn't have (or had only a later part of).
  final int imported;

  /// Keys this device already had, at least as complete.
  final int alreadyHad;

  /// Entries that weren't usable Megolm keys.
  final int invalid;

  int get total => imported + alreadyHad + invalid;
}

class MatrixKeyExport {
  /// The keys this device can decrypt with, in the export format, each from
  /// the earliest message index it knows.
  static Future<List<Map<String, dynamic>>> collect(Client client) async {
    final userId = client.userID;
    if (userId == null) return [];

    final stored = await client.database.getAllInboundGroupSessions();
    final sessions = <Map<String, dynamic>>[];
    var skipped = 0;
    for (final (i, entry) in stored.indexed) {
      // Unpickling is synchronous: let frames through on big accounts.
      if (i % 200 == 199) await Future<void>.delayed(Duration.zero);
      try {
        final key = SessionKey.fromDb(entry, userId);
        final session = key.inboundGroupSession;
        if (session == null) {
          skipped++;
          continue;
        }
        sessions.add({
          "algorithm": AlgorithmTypes.megolmV1AesSha2,
          "forwarding_curve25519_key_chain": key.forwardingCurve25519KeyChain,
          "room_id": key.roomId,
          "sender_key": key.senderKey,
          "sender_claimed_keys": key.senderClaimedKeys,
          "session_id": key.sessionId,
          "session_key": session.exportAtFirstKnownIndex(),
          // MSC4268 (spec v1.19): whether the session's creator agreed it
          // may be shared with people invited later. Read from the stored
          // key, under any of the names clients have used.
          "shared_history": _sharedHistory(key.content),
        });
      } catch (e, s) {
        skipped++;
        Log.onError(e, s, content: "Key export: skipped an unreadable key");
      }
    }
    if (skipped > 0) Log.i("Key export: skipped $skipped unreadable keys");
    return sessions;
  }

  /// Exports every key into the armored text of a key file.
  static Future<({String file, int count})> export(
      Client client, String passphrase) async {
    final sessions = await collect(client);
    final file = await MegolmKeyFile.encrypt(sessions, passphrase);
    return (file: file, count: sessions.length);
  }

  /// Decrypts [file] and stores its keys. New keys are also uploaded to the
  /// account's message backup, when one is set up.
  static Future<KeyImportResult> import(
      Client client, String file, String passphrase,
      {void Function(int done, int total)? onProgress}) async {
    final keyManager = client.encryption?.keyManager;
    if (keyManager == null) {
      throw StateError("Encryption isn't available on this account");
    }

    final sessions = await MegolmKeyFile.decrypt(file, passphrase);
    var imported = 0, alreadyHad = 0, invalid = 0;
    for (final (i, s) in sessions.indexed) {
      onProgress?.call(i, sessions.length);
      final roomId = s["room_id"], sessionId = s["session_id"];
      final senderKey = s["sender_key"], sessionKey = s["session_key"];
      if (s["algorithm"] != AlgorithmTypes.megolmV1AesSha2 ||
          roomId is! String ||
          sessionId is! String ||
          senderKey is! String ||
          sessionKey is! String) {
        invalid++;
        continue;
      }
      final claimed = s["sender_claimed_keys"];
      final chain = s["forwarding_curve25519_key_chain"];
      // Loads a stored key into memory, so setInboundGroupSession compares
      // against it instead of overwriting it with a less complete one.
      final before =
          await keyManager.loadInboundGroupSession(roomId, sessionId);
      try {
        await keyManager.setInboundGroupSession(
          roomId,
          sessionId,
          senderKey,
          {
            "algorithm": AlgorithmTypes.megolmV1AesSha2,
            "room_id": roomId,
            "session_id": sessionId,
            "session_key": sessionKey,
            "forwarding_curve25519_key_chain":
                chain is List ? chain.whereType<String>().toList() : <String>[],
            if (s["shared_history"] == true) "shared_history": true,
          },
          forwarded: true,
          senderClaimedKeys: claimed is Map
              ? {
                  for (final e in claimed.entries)
                    if (e.key is String && e.value is String)
                      e.key as String: e.value as String,
                }
              : null,
        );
      } catch (e, s) {
        invalid++;
        Log.onError(e, s, content: "Key import: a key couldn't be stored");
        continue;
      }
      final after = keyManager.getInboundGroupSession(roomId, sessionId);
      if (after == null) {
        // setInboundGroupSession drops keys it can't read.
        invalid++;
      } else if (identical(after, before)) {
        alreadyHad++;
      } else {
        imported++;
      }
    }
    onProgress?.call(sessions.length, sessions.length);
    return KeyImportResult(
        imported: imported, alreadyHad: alreadyHad, invalid: invalid);
  }

  static bool _sharedHistory(Map<String, dynamic> content) =>
      content["shared_history"] == true ||
      content["m.shared_history"] == true ||
      content["org.matrix.msc3061.shared_history"] == true;
}
