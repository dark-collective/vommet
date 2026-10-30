// Vommet: local data encryption, the key file fallback: keys/master.key
// ("VDK1" + the 32-byte master key, mode 0600 in a 0700 folder). Used when
// there is no keyring (operator decision: Linux without a Secret Service,
// and macOS until the builds are signed). The data is then protected by the
// user account's file permissions, as it is today, and the key can be moved
// to a keyring later.
import 'dart:io';
import 'dart:typed_data';

import 'package:commet/security/key_vault/key_file_io.dart';
import 'package:commet/security/key_vault/key_hierarchy.dart';
import 'package:commet/security/key_vault/keystore_document.dart';
import 'package:commet/security/key_vault/master_key_store.dart';
import 'package:path/path.dart' as p;

class FileKeyStore extends MasterKeyStore {
  FileKeyStore(String keysDirectory)
      : _file = KeyFileIo(p.join(keysDirectory, fileName), _magic);

  static const String fileName = "master.key";
  static const List<int> _magic = [0x56, 0x44, 0x4B, 0x31]; // "VDK1"

  final KeyFileIo _file;

  String get path => _file.path;

  @override
  KeyStoreKind get kind => KeyStoreKind.file;

  @override
  String get name => "Key file";

  @override
  Future<StoreAvailability> availability() async => StoreAvailability.available;

  @override
  Future<StoreReadResult> read({bool interactive = false}) async {
    try {
      final key = await _file.read();
      if (key == null) return const StoreEmpty();
      if (key.length != KeyHierarchy.keyLength) {
        return const StoreNotAKey("the key file is damaged");
      }
      return StoreFound(key);
    } on FileSystemException catch (e) {
      return StoreUnreachable("can't read the key file: ${e.message}");
    } on FormatException catch (e) {
      return StoreNotAKey("the key file is damaged: ${e.message}");
    }
  }

  @override
  Future<void> write(Uint8List key) async {
    try {
      await _file.write(key);
    } on FileSystemException catch (e) {
      throw KeyStoreException("can't write the key file: ${e.message}");
    } on KeyFileNotPrivate {
      throw KeyStoreException(
          "the key file can't be made readable by this user only");
    }
  }

  @override
  Future<void> archive() async {
    try {
      await _file.archive();
    } on FileSystemException catch (e) {
      throw KeyStoreException("can't set the key file aside: ${e.message}");
    }
  }

  /// master.key.archived-*: plaintext keys, like master.key itself. The
  /// vault deletes them once the key is kept in a keyring
  /// ([KeyVault] housekeeping) and keeps at most
  /// [MasterKeyStore.archivesKept] otherwise.
  @override
  Future<List<Uint8List>> archivedKeys() async => [
        for (final key in await _file.readArchives())
          if (key.length == KeyHierarchy.keyLength) key,
      ];

  @override
  Future<void> pruneArchives({int keep = MasterKeyStore.archivesKept}) =>
      _file.pruneArchives(keep);

  @override
  Future<void> delete() async {
    try {
      await _file.delete();
    } on FileSystemException catch (e) {
      throw KeyStoreException("can't delete the key file: ${e.message}");
    }
  }
}
