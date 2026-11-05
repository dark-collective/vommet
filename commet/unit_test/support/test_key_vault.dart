// Vommet: a key vault for unit tests, its master key in a key file under
// [directory] (no platform key store).
import 'package:commet/security/key_vault/file_key_store.dart';
import 'package:commet/security/key_vault/key_vault.dart';
import 'package:commet/security/key_vault/keystore_file.dart';

/// A vault on [directory]; unlocked (and the key made, when there is none
/// yet) unless [unlock] is false. Several on one directory behave like the
/// engines of one app.
Future<KeyVault> testKeyVault(String directory,
    {bool allowCreate = true, bool unlock = true}) async {
  final vault = KeyVault(
    keystoreFile: KeystoreFile(directory),
    fileStore: FileKeyStore(directory),
    preferredStores: const [],
    allowCreate: allowCreate,
    noKeyringReason: "test",
  );
  if (unlock) await vault.unlock();
  return vault;
}
