// Local data encryption: the shipped build and the real keyring (Vommet,
// 2026-10-27, LOCAL-DATA-ENCRYPTION.md phase 7).
//
// The app as built has the SQLite3 Multiple Ciphers library (a plain SQLite
// would open encrypted files as garbage; this is the packaging guard at run
// time). Under the CI desktop session (run.sh starts an unlocked GNOME
// Keyring and passes IT_KEYRING), the vault keeps its key in the keyring,
// not the key file, and the Secret Service store talks to the real
// gnome-keyring over the encrypted dh-ietf1024 session; a key written over
// one session kind reads back over the other.

import 'dart:io';

import 'package:commet/security/key_vault/key_hierarchy.dart';
import 'package:commet/security/key_vault/key_vault.dart';
import 'package:commet/security/key_vault/keystore_document.dart';
import 'package:commet/security/key_vault/master_key_store.dart';
import 'package:commet/security/key_vault/platform_key_stores.dart';
import 'package:commet/security/key_vault/secret_service_key_store.dart';
import 'package:commet/utils/database/encrypted_open.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../extensions/common_flows.dart';

const _keyring = bool.fromEnvironment("IT_KEYRING");

void _log(String s) {
  // ignore: avoid_print
  print("LDKEYS $s");
}

void main() {
  testWidgets("the build has the cipher and the vault uses the keyring",
      (tester) async {
    final app = await tester.setupApp();
    await tester.pumpWidget(app);

    final version = EncryptedOpen.requireCipher();
    _log("cipher: $version");
    expect(version, contains("SQLite3 Multiple Ciphers"));

    final vault = KeyVault.instance!;
    final status = vault.status;
    _log("vault: ${status.state.name} in ${status.store?.id}"
        "${status.fallbackReason == null ? "" : " (${status.fallbackReason})"}");
    expect(status.isReady, isTrue);
    if (!Platform.isLinux || !_keyring) return;

    expect(status.store, KeyStoreKind.keyring);
    expect(status.fileNoticeDue, isFalse);
    final keys = await PlatformKeyStores.keysDirectory();
    expect(File(p.join(keys, "master.key")).existsSync(), isFalse);

    // The real gnome-keyring, under an item of its own: the encrypted
    // session is used, and a key crosses between session kinds.
    final appId =
        "im.nether.chat.it-${KeyHierarchy.hex(KeyHierarchy.randomBytes(4))}";
    final dh = SecretServiceKeyStore(appId: appId);
    final plain = SecretServiceKeyStore(appId: appId, plainOnly: true);
    try {
      expect(await dh.availability(), StoreAvailability.available);
      final first = KeyHierarchy.newMasterKey();
      await dh.write(first);
      expect(dh.lastSessionAlgorithm, DhIetf1024Exchange.algorithm);
      final viaPlain = await plain.read();
      expect(plain.lastSessionAlgorithm, "plain");
      expect((viaPlain as StoreFound).key, first);

      final second = KeyHierarchy.newMasterKey();
      await plain.write(second);
      final viaDh = await dh.read();
      expect(dh.lastSessionAlgorithm, DhIetf1024Exchange.algorithm);
      expect((viaDh as StoreFound).key, second);
      _log("gnome-keyring: dh session round-trips both ways");
    } finally {
      await dh.delete();
    }
    expect(await dh.read(), isA<StoreEmpty>());
  });
}
