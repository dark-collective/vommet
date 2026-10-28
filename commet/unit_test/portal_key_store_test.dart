// Vommet: local data encryption, the Flatpak Secret portal store with a fake
// portal secret: the master key round-trips wrapped in keys/master.wrapped
// (never in the clear), a changed portal secret reads as "no key here", and
// a portal that fails reads as unreachable, not empty.
import 'dart:io';
import 'dart:typed_data';

import 'package:commet/security/key_vault/key_hierarchy.dart';
import 'package:commet/security/key_vault/master_key_store.dart';
import 'package:commet/security/key_vault/portal_key_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

bool _contains(List<int> haystack, List<int> needle) {
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    var match = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        match = false;
        break;
      }
    }
    if (match) return true;
  }
  return false;
}

void main() {
  late Directory root;
  late String keys;
  late Uint8List portalSecret;
  var failing = false;

  PortalKeyStore store() => PortalKeyStore(keys, secretSource: () async {
        if (failing) throw const SocketException("no portal");
        return Uint8List.fromList(portalSecret);
      });

  setUp(() async {
    root = await Directory(p.join(Directory.current.path, ".dart_tool"))
        .createTemp("portal_key_store_test_");
    keys = p.join(root.path, "keys");
    portalSecret = KeyHierarchy.randomBytes(64);
    failing = false;
  });

  tearDown(() async {
    await root.delete(recursive: true);
  });

  test("round trip, wrapped on disk", () async {
    expect(await store().availability(), StoreAvailability.available);
    expect(await store().read(), isA<StoreEmpty>());
    final key = KeyHierarchy.newMasterKey();
    await store().write(key);
    final read = await store().read();
    expect(read, isA<StoreFound>());
    expect((read as StoreFound).key, key);

    final file = File(p.join(keys, PortalKeyStore.fileName)).readAsBytesSync();
    expect(file.sublist(0, 4), "VPW1".codeUnits);
    expect(file.length, 4 + 24 + 32 + 16);
    expect(_contains(file, key), isFalse);

    await store().delete();
    expect(await store().read(), isA<StoreEmpty>());
  });

  test("a changed portal secret no longer has the key", () async {
    await store().write(KeyHierarchy.newMasterKey());
    portalSecret = KeyHierarchy.randomBytes(64);
    expect(await store().read(), isA<StoreEmpty>());
  });

  test("a failing portal is unreachable, not empty", () async {
    await store().write(KeyHierarchy.newMasterKey());
    failing = true;
    expect(await store().availability(), StoreAvailability.unavailable);
    expect(await store().read(), isA<StoreUnreachable>());
    expect(() => store().write(KeyHierarchy.newMasterKey()),
        throwsA(isA<KeyStoreException>()));
  });

  test("a damaged wrapped key is unreachable", () async {
    await store().write(KeyHierarchy.newMasterKey());
    final file = File(p.join(keys, PortalKeyStore.fileName));
    file.writeAsBytesSync(file.readAsBytesSync().sublist(0, 30));
    expect(await store().read(), isA<StoreUnreachable>());
  });
}
