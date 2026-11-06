// Vommet: local data encryption, the Windows DPAPI key store. Off Windows it
// only reports itself unavailable; on Windows (the GitHub Windows job) the FFI
// to crypt32 is exercised for real: the key round-trips through
// CryptProtectData/CryptUnprotectData, the file is "VDP1" + a blob that
// doesn't contain the key, a damaged blob is unreachable (never a wrong key),
// and the vault keeps a new key in DPAPI rather than the key file.
import 'dart:io';
import 'dart:typed_data';

import 'package:commet/security/key_vault/dpapi_key_store.dart';
import 'package:commet/security/key_vault/file_key_store.dart';
import 'package:commet/security/key_vault/key_hierarchy.dart';
import 'package:commet/security/key_vault/key_vault.dart';
import 'package:commet/security/key_vault/keystore_document.dart';
import 'package:commet/security/key_vault/keystore_file.dart';
import 'package:commet/security/key_vault/master_key_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

bool _contains(List<int> haystack, List<int> needle) {
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    var j = 0;
    while (j < needle.length && haystack[i + j] == needle[j]) {
      j++;
    }
    if (j == needle.length) return true;
  }
  return false;
}

void main() {
  late Directory root;
  late String keys;

  setUp(() async {
    root = await Directory(p.join(Directory.current.path, ".dart_tool"))
        .createTemp("dpapi_test_");
    keys = p.join(root.path, "keys");
  });

  tearDown(() async {
    await root.delete(recursive: true);
  });

  test("off Windows the store is unavailable", () async {
    if (Platform.isWindows) return;
    final store = DpapiKeyStore(keys);
    expect(store.kind, KeyStoreKind.dpapi);
    expect(await store.availability(), StoreAvailability.unavailable);
    expect(await store.read(), isA<StoreEmpty>());
  });

  group("on Windows", skip: !Platform.isWindows, () {
    test("the key round-trips and the file doesn't hold it", () async {
      final store = DpapiKeyStore(keys);
      expect(await store.availability(), StoreAvailability.available);
      expect(await store.read(), isA<StoreEmpty>());
      final key = KeyHierarchy.newMasterKey();
      await store.write(Uint8List.fromList(key));
      final read = await DpapiKeyStore(keys).read();
      expect(read, isA<StoreFound>());
      expect((read as StoreFound).key, key);
      final bytes =
          File(p.join(keys, DpapiKeyStore.fileName)).readAsBytesSync();
      expect(bytes.sublist(0, 4), "VDP1".codeUnits);
      expect(bytes.length, greaterThan(4 + key.length));
      expect(_contains(bytes, key), isFalse);
      await store.delete();
      expect(await store.read(), isA<StoreEmpty>());
    });

    test("a damaged blob is unreachable, not a wrong key", () async {
      final store = DpapiKeyStore(keys);
      await store.write(KeyHierarchy.newMasterKey());
      final file = File(p.join(keys, DpapiKeyStore.fileName));
      final bytes = file.readAsBytesSync();
      bytes[bytes.length - 8] ^= 0x5a;
      file.writeAsBytesSync(bytes);
      expect(await store.read(), isA<StoreUnreachable>());
    });

    test("the vault keeps a new key in DPAPI", () async {
      final vault = KeyVault(
          keystoreFile: KeystoreFile(keys),
          fileStore: FileKeyStore(keys),
          preferredStores: [DpapiKeyStore(keys)],
          allowCreate: true);
      final status = await vault.unlock();
      expect(status.state, VaultState.ready);
      expect(status.store, KeyStoreKind.dpapi);
      expect(status.fileNoticeDue, isFalse);
      expect(File(p.join(keys, "master.key")).existsSync(), isFalse);
      await vault.idle();
    });
  });
}
