// Vommet: local data encryption, the key hierarchy. One random master key M
// per install (all accounts); every key that protects a file on disk is
// derived from it with HKDF-SHA256, so M itself is never handed to a
// database, a worker or another isolate.
//
//   K_db       = HKDF(M, salt = <owner salt>, info = "vommet db v1 <role>")
//   K_media    = HKDF(M, salt = media_salt, info = "vommet media cache v2 master")
//   K_files    = HKDF(M, salt = app_salt, info = "vommet files v1")
//   check      = hex(HKDF(M, info = "vommet keystore v1 check"))[0:16]
//
// The info strings are part of the on-disk format: changing one makes every
// encrypted database unreadable. unit_test/key_hierarchy_test.dart pins them
// with fixed vectors.
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/dart.dart';
import 'package:cryptography/cryptography.dart';

/// The databases that get a key of their own.
enum DatabaseRole {
  /// An account's message store (`<drift dir>/<account>/data.db`).
  data("data.db"),

  /// An account's encrypted search index (`search_index.db`).
  searchIndex("search_index.db"),

  /// The app's file cache index (`<db>/app/app_data.db`).
  appData("app_data.db");

  const DatabaseRole(this.fileName);

  /// The file name, which is also the HKDF info suffix.
  final String fileName;

  /// Whether the database belongs to one account (its salt is the
  /// account's) rather than to the app.
  bool get perAccount => this != DatabaseRole.appData;
}

class KeyHierarchy {
  static const int keyLength = 32;
  static const int saltLength = 32;

  static const String checkInfo = "vommet keystore v1 check";
  static const String dbInfoPrefix = "vommet db v1 ";
  static const String mediaInfo = "vommet media cache v2 master";
  static const String filesInfo = "vommet files v1";
  static const String portalKekInfo = "vommet portal kek v1";

  static final _hkdf = DartHkdf(hmac: DartHmac.sha256(), outputLength: 32);

  static Future<Uint8List> derive(List<int> ikm,
      {List<int> salt = const [], required String info}) async {
    if (ikm.length != keyLength) {
      throw ArgumentError("Key material must be $keyLength bytes");
    }
    final key = await _hkdf.deriveKey(
        secretKey: SecretKeyData(ikm), nonce: salt, info: utf8.encode(info));
    return Uint8List.fromList(await key.extractBytes());
  }

  /// The value kept in keystore.json that tells "this is the right master
  /// key" without opening a database. Not secret: 8 bytes of an HKDF output.
  static Future<String> checkValue(List<int> master) async =>
      hex(await derive(master, info: checkInfo)).substring(0, 16);

  /// The SQLCipher key of one database file.
  static Future<Uint8List> databaseKey(
          List<int> master, List<int> salt, DatabaseRole role) =>
      derive(master, salt: salt, info: "$dbInfoPrefix${role.fileName}");

  /// The media cache's master key (handed to MediaCacheCrypto.fromMasterKey).
  static Future<Uint8List> mediaKey(List<int> master, List<int> mediaSalt) =>
      derive(master, salt: mediaSalt, info: mediaInfo);

  /// Reserved for other sealed files (voice transcripts and the like).
  static Future<Uint8List> filesKey(List<int> master, List<int> appSalt) =>
      derive(master, salt: appSalt, info: filesInfo);

  static Uint8List randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
        List<int>.generate(length, (_) => random.nextInt(256)));
  }

  static Uint8List newMasterKey() => randomBytes(keyLength);
  static Uint8List newSalt() => randomBytes(saltLength);

  static String hex(List<int> bytes) {
    final out = StringBuffer();
    for (final b in bytes) {
      out.write(b.toRadixString(16).padLeft(2, "0"));
    }
    return out.toString();
  }

  /// Constant-time comparison (the lengths are not secret).
  static bool equal(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
