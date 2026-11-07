import 'dart:io';
import 'dart:typed_data';

import 'package:commet/debug/log.dart';
import 'package:commet/security/database_keys.dart';
import 'package:commet/security/key_vault/key_vault.dart';
import 'package:commet/security/migration/database_migration.dart';

/// Vommet: where the key of the encrypted part of the media cache comes
/// from. The app's key vault in the app ([VaultMediaCacheKey]); tests may
/// pass their own vault.
abstract class MediaCacheKeySource {
  /// The current key and its [stamp]. Throws [MediaCacheKeyUnreadable] when
  /// there is no key this run (sealed caching is then off for the run).
  Future<({Uint8List key, String stamp})> load();

  /// Identifies the current key without revealing it; cheap enough to call
  /// before every use (another engine of the app may have changed it).
  /// Null when there is none.
  Future<String?> stamp();

  /// A new key (sign-out): what the old one sealed can't be opened again.
  Future<void> forget();
}

/// Vommet (local data encryption): the media cache key is derived from the
/// vault's master key and the media salt in keystore.json
/// (LOCAL-DATA-ENCRYPTION.md §3). Signing out rotates the salt, so whatever
/// a failed delete left behind can't be decrypted. A vault that isn't ready
/// means no sealed caching for the run.
///
/// Until local data encryption, the key was a file next to the databases
/// ("<database dir>/app/media_cache.key", see [deleteLegacyKeyFile]); what
/// it sealed is wiped (it is a cache) and the file is overwritten and
/// deleted.
class VaultMediaCacheKey implements MediaCacheKeySource {
  VaultMediaCacheKey([this._vault]);

  final KeyVault? _vault;
  KeyVault? get _current =>
      _vault ?? DatabaseKeys.debugVault ?? KeyVault.instance;

  /// keystore.json as last read: only re-read when it changed.
  ({DateTime modified, int size})? _seen;

  @override
  Future<({Uint8List key, String stamp})> load() async {
    final vault = _current;
    if (vault == null || !vault.status.isReady) {
      throw MediaCacheKeyUnreadable(
          "the key vault isn't ready (${vault?.status.state.name ?? "none"})");
    }
    await _refresh(vault, force: true);
    try {
      // The stamp is read with the salt the key is derived from (no await
      // between them).
      final stamp = vault.mediaKeyStamp;
      final key = await vault.mediaKey();
      if (stamp == null) throw MediaCacheKeyUnreadable("no media salt");
      return (key: key, stamp: stamp);
    } on VaultNotReady catch (e) {
      throw MediaCacheKeyUnreadable(
          "the key vault isn't ready (${e.status.state.name})");
    }
  }

  @override
  Future<String?> stamp() async {
    final vault = _current;
    if (vault == null || !vault.status.isReady) return null;
    await _refresh(vault);
    return vault.mediaKeyStamp;
  }

  @override
  Future<void> forget() async {
    final vault = _current;
    if (vault == null || !vault.status.isReady) {
      // The sealed entries are wiped anyway; the next ready run keeps the
      // old salt, which opens nothing that is left.
      Log.w("Media cache key not rotated: the key vault isn't ready");
      return;
    }
    await vault.rotateMediaKey();
    _seen = null;
  }

  Future<void> _refresh(KeyVault vault, {bool force = false}) async {
    try {
      final stat = await FileStat.stat(vault.keystoreFile.path);
      final seen = (modified: stat.modified, size: stat.size);
      if (!force && seen == _seen) return;
      await vault.refresh();
      _seen = seen;
    } catch (_) {}
  }

  /// The media cache key file of versions before local data encryption:
  /// overwritten and deleted. Never throws.
  static Future<void> deleteLegacyKeyFile(String path) async {
    try {
      if (await FileSystemEntity.type(path) != FileSystemEntityType.file) {
        return;
      }
      await DatabaseMigrator.secureDelete(path);
      Log.i("Deleted the old media cache key file");
    } catch (error) {
      Log.w("Couldn't delete the old media cache key file: $error");
    }
  }
}

/// Vommet: there is no media cache key this run.
class MediaCacheKeyUnreadable implements Exception {
  MediaCacheKeyUnreadable(this.message);

  final String message;

  @override
  String toString() => "Media cache key unreadable: $message";
}
