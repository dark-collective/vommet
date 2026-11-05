// Vommet: local data encryption, which key store each platform uses and the
// process-wide KeyVault (native platforms only; see local_data_keys.dart).
//
// Preferred stores, best first (the key file is always the last resort):
// - Linux Flatpak: Secret portal, then the Secret Service.
// - Linux: the Secret Service (GNOME Keyring, KWallet, KeePassXC).
// - Android, iOS: flutter_secure_storage (Keystore / keychain).
// - macOS: the key file while builds aren't signed (macosKeychainEnabled);
//   the keychain through flutter_secure_storage once they are.
// - Windows: DPAPI.
import 'dart:io';

import 'package:commet/config/app_config.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/security/key_vault/dpapi_key_store.dart';
import 'package:commet/security/key_vault/file_key_store.dart';
import 'package:commet/security/key_vault/key_vault.dart';
import 'package:commet/security/key_vault/keystore_file.dart';
import 'package:commet/security/key_vault/master_key_store.dart';
import 'package:commet/security/key_vault/portal_key_store.dart';
import 'package:commet/security/key_vault/secret_service_key_store.dart';
import 'package:commet/security/key_vault/secure_storage_key_store.dart';
import 'package:path/path.dart' as p;

/// The macOS keychain switch. Unsigned (ad-hoc) builds can't use the
/// data-protection keychain, and the login keychain asks again after every
/// update, so macOS keeps the key in the key file until builds are signed.
/// Turning this on moves existing installs to the keychain automatically at
/// their next start (unless the user pinned the file).
const bool macosKeychainEnabled = false;

class PlatformKeyStores {
  /// The preferred stores of this platform, best first, and the reason
  /// there is none (recorded, and shown in the settings later).
  static (List<MasterKeyStore>, String?) preferred(String keysDirectory) {
    if (Platform.isLinux) {
      return (
        [
          if (PlatformUtils.isFlatpak) PortalKeyStore(keysDirectory),
          SecretServiceKeyStore(),
        ],
        null
      );
    }
    if (Platform.isAndroid || Platform.isIOS) {
      return ([SecureStorageKeyStore()], null);
    }
    if (Platform.isMacOS) {
      if (macosKeychainEnabled) return ([SecureStorageKeyStore()], null);
      return (const <MasterKeyStore>[], "macOS builds aren't signed yet");
    }
    if (Platform.isWindows) {
      return ([DpapiKeyStore(keysDirectory)], null);
    }
    return (const <MasterKeyStore>[], "no key store on this platform");
  }

  /// `<database dir>/keys`.
  static Future<String> keysDirectory() async =>
      p.join(await AppConfig.getDatabasePath(), "keys");

  /// Sets up [KeyVault.instance] and unlocks it. Only the UI engine may
  /// create a key or write keystore.json ([headless] engines read).
  /// [interactive] (default: not [headless]) lets a locked keyring ask for
  /// its password; [allowCreate] false keeps even the UI engine from making
  /// a new key (encrypted files whose keystore.json is gone: a new key
  /// would never open them).
  static Future<KeyVault> init(
      {required bool headless, bool? interactive, bool? allowCreate}) async {
    final ask = interactive ?? !headless;
    final existing = KeyVault.instance;
    if (existing != null) {
      if (!existing.status.isReady) {
        await existing.unlock(interactive: ask);
      }
      return existing;
    }
    final directory = await keysDirectory();
    final (stores, reason) = preferred(directory);
    final vault = KeyVault(
      keystoreFile: KeystoreFile(directory),
      fileStore: FileKeyStore(directory),
      preferredStores: stores,
      allowCreate: allowCreate ?? !headless,
      noKeyringReason: reason,
      // macOS without the keychain is a decision, not a missing keyring.
      noticeWhenNoKeyring: !Platform.isMacOS,
    );
    KeyVault.instance = vault;
    await vault.unlock(interactive: ask);
    return vault;
  }
}
