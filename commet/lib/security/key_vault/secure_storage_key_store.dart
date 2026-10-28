// Vommet: local data encryption, the master key in the platform keystore
// through flutter_secure_storage: the Android Keystore (encrypted shared
// preferences), the iOS keychain, and the macOS keychain once macOS builds
// are signed (see platform_key_stores.dart). The value is the key in base64.
//
// Android: resetOnError is off, so a keystore the plugin can't decrypt is
// reported as unreachable instead of being wiped silently (the databases
// would then be lost for good). iOS: the item is readable after the first
// unlock (background sync works with a locked phone) and never leaves the
// device (no iCloud keychain sync, not in backups).
import 'dart:convert';

import 'package:commet/security/key_vault/key_hierarchy.dart';
import 'package:commet/security/key_vault/keystore_document.dart';
import 'package:commet/security/key_vault/master_key_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageKeyStore extends MasterKeyStore {
  SecureStorageKeyStore({FlutterSecureStorage? storage})
      : _storage = storage ?? defaultStorage;

  static const String storageKey = "vommet_master_key_v1";

  static const FlutterSecureStorage defaultStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: false),
    iOptions: IOSOptions(
        accessibility: KeychainAccessibility.first_unlock_this_device,
        synchronizable: false),
    mOptions: MacOsOptions(
        accessibility: KeychainAccessibility.first_unlock_this_device,
        synchronizable: false),
  );

  final FlutterSecureStorage _storage;

  @override
  KeyStoreKind get kind => KeyStoreKind.keyring;

  @override
  String get name => "platform keystore";

  @override
  Future<StoreAvailability> availability() async {
    try {
      await _storage.containsKey(key: storageKey);
      return StoreAvailability.available;
    } catch (_) {
      return StoreAvailability.unavailable;
    }
  }

  @override
  Future<StoreReadResult> read({bool interactive = false}) async {
    final String? value;
    try {
      value = await _storage.read(key: storageKey);
    } on PlatformException catch (e) {
      return StoreUnreachable("the platform keystore failed (${e.code})");
    } catch (e) {
      return StoreUnreachable("no platform keystore: ${e.runtimeType}");
    }
    if (value == null) return const StoreEmpty();
    try {
      final key = Uint8List.fromList(base64.decode(value));
      if (key.length != KeyHierarchy.keyLength) {
        return const StoreUnreachable("the keystore item isn't a key");
      }
      return StoreFound(key);
    } on FormatException {
      return const StoreUnreachable("the keystore item isn't a key");
    }
  }

  @override
  Future<void> write(Uint8List key) async {
    try {
      await _storage.write(key: storageKey, value: base64.encode(key));
    } on PlatformException catch (e) {
      throw KeyStoreException("the platform keystore failed (${e.code})");
    } catch (e) {
      throw KeyStoreException("no platform keystore: ${e.runtimeType}");
    }
  }

  /// Where [archive] puts a key: `vommet_master_key_v1.archived-<time>`.
  static const String archivedPrefix = "$storageKey.archived-";

  @override
  Future<void> archive() async {
    try {
      final value = await _storage.read(key: storageKey);
      if (value == null) return;
      final archived =
          "$archivedPrefix${DateTime.now().millisecondsSinceEpoch}";
      await _storage.write(key: archived, value: value);
      if (await _storage.read(key: archived) != value) {
        throw KeyStoreException("the platform keystore didn't keep the copy");
      }
      await _storage.delete(key: storageKey);
    } on KeyStoreException {
      rethrow;
    } on PlatformException catch (e) {
      throw KeyStoreException("the platform keystore failed (${e.code})");
    } catch (e) {
      throw KeyStoreException("no platform keystore: ${e.runtimeType}");
    }
  }

  @override
  Future<void> delete() async {
    try {
      await _storage.delete(key: storageKey);
    } on PlatformException catch (e) {
      throw KeyStoreException("the platform keystore failed (${e.code})");
    } catch (e) {
      throw KeyStoreException("no platform keystore: ${e.runtimeType}");
    }
  }
}
