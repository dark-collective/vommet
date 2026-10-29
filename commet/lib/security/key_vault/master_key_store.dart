// Vommet: local data encryption, the places the master key can be kept.
import 'dart:typed_data';

import 'package:commet/security/key_vault/keystore_document.dart';

/// Whether a store can be used right now.
enum StoreAvailability {
  available,

  /// It exists but is locked (a keyring whose collection needs the user's
  /// password); [MasterKeyStore.read] with `interactive: true` may prompt.
  locked,

  /// Not here (no keyring daemon, no session bus, not supported on this
  /// platform or build).
  unavailable,
}

sealed class StoreReadResult {
  const StoreReadResult();
}

class StoreFound extends StoreReadResult {
  StoreFound(this.key);
  final Uint8List key;
}

/// The store answered and holds no key.
class StoreEmpty extends StoreReadResult {
  const StoreEmpty();
}

/// The store is locked and wasn't (or couldn't be) unlocked.
class StoreLocked extends StoreReadResult {
  const StoreLocked();
}

/// The store couldn't be reached or failed. May pass (a D-Bus hiccup, a
/// timeout): what the store holds is never set aside or written over
/// because of it.
class StoreUnreachable extends StoreReadResult {
  const StoreUnreachable(this.reason);
  final String reason;
}

/// The store answered, and what it holds is not a key (a damaged key file,
/// a keyring item that doesn't decode). Unlike a plain [StoreUnreachable],
/// this is known for sure, so the vault may set it aside.
class StoreNotAKey extends StoreUnreachable {
  const StoreNotAKey(super.reason);
}

/// A failed write or delete. [reason] never contains key material.
class KeyStoreException implements Exception {
  KeyStoreException(this.reason, {this.locked = false});
  final String reason;
  final bool locked;
  @override
  String toString() => "KeyStoreException: $reason";
}

abstract class MasterKeyStore {
  KeyStoreKind get kind;

  /// A short name for logs and the settings page ("Secret Service",
  /// "Keychain", ...).
  String get name;

  Future<StoreAvailability> availability();

  /// The stored key. With [interactive], a locked store may ask the user to
  /// unlock it (a keyring prompt); headless engines never prompt.
  Future<StoreReadResult> read({bool interactive = false});

  /// Stores [key], replacing any key there. Throws [KeyStoreException].
  /// The vault never calls it over a different key: it [archive]s that one
  /// first (data may still depend on it).
  Future<void> write(Uint8List key);

  /// Sets the key this store holds aside under a name of its own that
  /// [read] never finds (a keyring item with other attributes, a renamed
  /// file), so a new key can be written without the old one being lost.
  /// Nothing to do when the store holds nothing. Throws [KeyStoreException].
  Future<void> archive();

  /// Removes the key. Throws [KeyStoreException].
  Future<void> delete();

  /// The keys [archive] set aside that can still be read, newest first
  /// (the vault looks for the recorded key among them when the store
  /// doesn't have it). Best effort: what can't be read is left out.
  Future<List<Uint8List>> archivedKeys() async => const [];

  /// Removes archived copies beyond the newest [keep] (0: all of them).
  /// Best effort.
  Future<void> pruneArchives({int keep = MasterKeyStore.archivesKept}) async {}

  /// How many archived keys a store keeps.
  static const int archivesKept = 3;
}
