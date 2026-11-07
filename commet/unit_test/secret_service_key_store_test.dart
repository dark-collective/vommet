// Vommet: local data encryption, the Secret Service key store against a
// small in-process Secret Service on a private D-Bus: the key is written to
// the default collection, read back, found again by a second client, and
// deleted; a locked collection reads as locked, and an interactive read
// unlocks it through a prompt; no service at all reads as unreachable. The
// session is the encrypted dh-ietf1024 one when the service offers it (the
// key never crosses the bus in the clear), plain otherwise; the exchange has
// a known-answer vector computed with Python and OpenSSL.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:commet/security/key_vault/file_key_store.dart';
import 'package:commet/security/key_vault/key_hierarchy.dart';
import 'package:commet/security/key_vault/key_vault.dart';
import 'package:commet/security/key_vault/keystore_document.dart';
import 'package:commet/security/key_vault/keystore_file.dart';
import 'package:commet/security/key_vault/master_key_store.dart';
import 'package:commet/security/key_vault/secret_service_key_store.dart';
import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const _root = "/org/freedesktop/secrets";
const _collectionPath = "$_root/collection/login";

Map<String, String> _ssDict(DBusValue v) =>
    v.asDict().map((k, v) => MapEntry(k.asString(), v.asString()));

class _Item {
  _Item(this.attributes, this.secret);
  final Map<String, String> attributes;
  List<int> secret;
}

class FakeSecretService {
  final items = <String, _Item>{};
  bool locked = false;
  bool dismissPrompts = false;
  int prompts = 0;

  /// Offer the encrypted session (gnome-keyring, KeePassXC do).
  bool offerDh = true;

  /// The algorithm of every session opened, in order.
  final algorithms = <String>[];

  /// Every secret value that crossed the bus, as sent.
  final wire = <List<int>>[];
  final _transports = <String, SecretTransport>{};
  int _next = 0;
  late DBusClient _client;
  final _objects = <String, _Object>{};

  Future<void> start(DBusAddress address) async {
    _client = DBusClient(address);
    await _client.requestName("org.freedesktop.secrets");
    await _export(_root, _service);
    await _export(_collectionPath, _collection,
        properties: (name) => name == "Locked" ? DBusBoolean(locked) : null);
  }

  Future<void> stop() => _client.close();

  Future<String> _export(String path,
      Future<DBusMethodResponse> Function(_Object o, DBusMethodCall c) handler,
      {DBusValue? Function(String name)? properties}) async {
    final object = _Object(DBusObjectPath(path), handler, properties);
    _objects[path] = object;
    await _client.registerObject(object);
    return path;
  }

  Future<DBusMethodResponse> _service(_Object o, DBusMethodCall call) async {
    switch (call.name) {
      case "OpenSession":
        final algorithm = call.values[0].asString();
        SecretTransport? transport;
        DBusValue output = const DBusString("");
        if (algorithm == DhIetf1024Exchange.algorithm) {
          if (!offerDh) {
            return DBusMethodErrorResponse(
                "org.freedesktop.DBus.Error.NotSupported");
          }
          final server = DhIetf1024Exchange();
          transport = await server
              .transport(call.values[1].asVariant().asByteArray().toList());
          output = DBusArray.byte(server.publicKey);
        } else if (algorithm != "plain") {
          return DBusMethodErrorResponse(
              "org.freedesktop.DBus.Error.NotSupported");
        }
        algorithms.add(algorithm);
        final path = await _export("$_root/session/${_next++}",
            (o, c) async => DBusMethodSuccessResponse());
        if (transport != null) _transports[path] = transport;
        return DBusMethodSuccessResponse(
            [DBusVariant(output), DBusObjectPath(path)]);
      case "ReadAlias":
        return DBusMethodSuccessResponse([DBusObjectPath(_collectionPath)]);
      case "SearchItems":
        final wanted = _ssDict(call.values[0]);
        final found = items.entries
            .where((e) => wanted.entries
                .every((w) => e.value.attributes[w.key] == w.value))
            .map((e) => DBusObjectPath(e.key))
            .toList();
        return DBusMethodSuccessResponse([
          DBusArray.objectPath(locked ? [] : found),
          DBusArray.objectPath(locked ? found : []),
        ]);
      case "Unlock":
        if (!locked) {
          return DBusMethodSuccessResponse(
              [call.values[0], DBusObjectPath("/")]);
        }
        final path = await _export("$_root/prompt/${_next++}", (p, c) async {
          if (c.name == "Prompt") {
            prompts++;
            scheduleMicrotask(() async {
              await Future<void>.delayed(const Duration(milliseconds: 20));
              if (!dismissPrompts) locked = false;
              await p.emitSignal("org.freedesktop.Secret.Prompt", "Completed", [
                DBusBoolean(dismissPrompts),
                DBusVariant(DBusArray.objectPath([]))
              ]);
            });
          }
          return DBusMethodSuccessResponse();
        });
        return DBusMethodSuccessResponse(
            [DBusArray.objectPath([]), DBusObjectPath(path)]);
      case "GetSecrets":
        final paths = call.values[0].asObjectPathArray();
        final session = call.values[1];
        if (locked) {
          return DBusMethodErrorResponse(
              "org.freedesktop.Secret.Error.IsLocked");
        }
        final transport = _transports[session.asObjectPath().value];
        final out = <DBusValue, DBusValue>{};
        for (final p in paths) {
          final item = items[p.value];
          if (item == null) continue;
          var (parameters, value) = (const <int>[], item.secret);
          if (transport != null) {
            (parameters, value) = await transport.encrypt(item.secret);
          }
          wire.add(value);
          out[p] = DBusStruct([
            session,
            DBusArray.byte(parameters),
            DBusArray.byte(value),
            const DBusString("text/plain"),
          ]);
        }
        return DBusMethodSuccessResponse(
            [DBusDict(DBusSignature("o"), DBusSignature("(oayays)"), out)]);
    }
    return DBusMethodErrorResponse.unknownMethod();
  }

  Future<DBusMethodResponse> _collection(_Object o, DBusMethodCall call) async {
    if (call.name != "CreateItem") {
      return DBusMethodErrorResponse.unknownMethod();
    }
    if (locked) {
      return DBusMethodErrorResponse("org.freedesktop.Secret.Error.IsLocked");
    }
    final props = call.values[0].asStringVariantDict();
    final attributes =
        _ssDict(props["org.freedesktop.Secret.Item.Attributes"]!);
    final fields = call.values[1].asStruct();
    var secret = fields[2].asByteArray().toList();
    wire.add(secret);
    final transport = _transports[fields[0].asObjectPath().value];
    if (transport != null) {
      secret =
          await transport.decrypt(fields[1].asByteArray().toList(), secret);
    }
    final replace = call.values[2].asBoolean();
    for (final entry in items.entries) {
      if (replace && _same(entry.value.attributes, attributes)) {
        entry.value.secret = secret;
        return DBusMethodSuccessResponse(
            [DBusObjectPath(entry.key), DBusObjectPath("/")]);
      }
    }
    final path = await _export("$_collectionPath/${_next++}", (o, c) async {
      if (c.name == "Delete") {
        items.remove(o.path.value);
        return DBusMethodSuccessResponse([DBusObjectPath("/")]);
      }
      return DBusMethodErrorResponse.unknownMethod();
    });
    items[path] = _Item(attributes, secret);
    return DBusMethodSuccessResponse(
        [DBusObjectPath(path), DBusObjectPath("/")]);
  }

  static bool _same(Map<String, String> a, Map<String, String> b) =>
      a.length == b.length && a.entries.every((e) => b[e.key] == e.value);
}

class _Object extends DBusObject {
  _Object(super.path, this.handler, this.properties);
  final Future<DBusMethodResponse> Function(_Object o, DBusMethodCall c)
      handler;
  final DBusValue? Function(String name)? properties;

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) =>
      handler(this, methodCall);

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    final value = properties?.call(name);
    return value == null
        ? DBusMethodErrorResponse.unknownProperty()
        : DBusGetPropertyResponse(value);
  }
}

void main() {
  if (!Platform.isLinux) return;

  late DBusServer server;
  late DBusAddress address;
  late FakeSecretService service;

  setUp(() async {
    server = DBusServer();
    address = await server.listenAddress(DBusAddress.unix(
        abstract:
            "vommet-ss-test-${KeyHierarchy.hex(KeyHierarchy.randomBytes(6))}"));
    service = FakeSecretService();
    await service.start(address);
  });

  tearDown(() async {
    await service.stop();
    await server.close();
  });

  SecretServiceKeyStore store({bool plainOnly = false}) =>
      SecretServiceKeyStore(
          clientFactory: () => DBusClient(address), plainOnly: plainOnly);

  bool onWire(List<int> key) {
    final text = utf8.encode(base64.encode(key));
    bool contains(List<int> haystack, List<int> needle) {
      for (var i = 0; i + needle.length <= haystack.length; i++) {
        var j = 0;
        while (j < needle.length && haystack[i + j] == needle[j]) {
          j++;
        }
        if (j == needle.length) return true;
      }
      return false;
    }

    return service.wire.any((w) => contains(w, text) || contains(w, key));
  }

  test("write, read back, find again and delete", () async {
    final key = KeyHierarchy.newMasterKey();
    expect(await store().availability(), StoreAvailability.available);
    expect(await store().read(), isA<StoreEmpty>());
    final writer = store();
    await writer.write(key);
    expect(writer.lastSessionAlgorithm, DhIetf1024Exchange.algorithm);
    final read = await store().read();
    expect(read, isA<StoreFound>());
    expect((read as StoreFound).key, key);
    expect(service.items.length, 1);
    expect(service.items.values.single.attributes["app"], "im.nether.chat");

    // Replacing keeps one item.
    final other = KeyHierarchy.newMasterKey();
    await store().write(other);
    expect(service.items.length, 1);
    expect(((await store().read()) as StoreFound).key, other);

    await store().delete();
    expect(service.items, isEmpty);
    expect(await store().read(), isA<StoreEmpty>());

    // Every session was the encrypted one, and the keys never crossed the
    // bus in the clear.
    expect(service.algorithms, everyElement(DhIetf1024Exchange.algorithm));
    expect(service.wire, isNotEmpty);
    expect(onWire(key), isFalse);
    expect(onWire(other), isFalse);
  });

  test("archive sets the key aside where read doesn't find it", () async {
    final key = KeyHierarchy.newMasterKey();
    await store().write(key);
    await store().archive();
    expect(await store().read(), isA<StoreEmpty>());
    expect(service.items.length, 1);
    final kept = service.items.values.single;
    expect(kept.attributes["kind"], "master-key-v1-archived");
    expect(kept.attributes["app"], "im.nether.chat");
    expect(kept.secret, utf8.encode(base64.encode(key)));

    // A new key next to it; deleting it leaves the archived one.
    final other = KeyHierarchy.newMasterKey();
    await store().write(other);
    expect(((await store().read()) as StoreFound).key, other);
    expect(service.items.length, 2);
    await store().delete();
    expect(service.items.length, 1);
    expect(service.items.values.single.secret, utf8.encode(base64.encode(key)));
    expect(onWire(key), isFalse);
  });

  test("a locked keyring isn't archived", () async {
    await store().write(KeyHierarchy.newMasterKey());
    service.locked = true;
    await expectLater(store().archive(), throwsA(isA<KeyStoreException>()));
    service.locked = false;
    expect(await store().read(), isA<StoreFound>());
  });

  test("a service without the encrypted session gets a plain one", () async {
    service.offerDh = false;
    final key = KeyHierarchy.newMasterKey();
    final writer = store();
    await writer.write(key);
    expect(writer.lastSessionAlgorithm, "plain");
    final read = await store().read();
    expect((read as StoreFound).key, key);
    expect(service.algorithms, everyElement("plain"));
    expect(onWire(key), isTrue);
  });

  test("an item written over a plain session reads over an encrypted one",
      () async {
    final key = KeyHierarchy.newMasterKey();
    await store(plainOnly: true).write(key);
    final read = await store().read();
    expect((read as StoreFound).key, key);
    expect(service.algorithms, ["plain", DhIetf1024Exchange.algorithm]);
  });

  test("a locked keyring reads as locked and unlocks through a prompt",
      () async {
    final key = Uint8List.fromList(KeyHierarchy.newMasterKey());
    await store().write(key);
    service.locked = true;
    expect(await store().availability(), StoreAvailability.locked);
    expect(await store().read(), isA<StoreLocked>());
    expect(service.prompts, 0);
    await expectLater(
        () => store().write(key), throwsA(isA<KeyStoreException>()));

    service.dismissPrompts = true;
    expect(await store().read(interactive: true), isA<StoreLocked>());
    expect(service.prompts, 1);

    service.dismissPrompts = false;
    final read = await store().read(interactive: true);
    expect(read, isA<StoreFound>());
    expect((read as StoreFound).key, key);
    expect(service.prompts, 2);
  });

  test("the exchange matches libsecret's (Python + OpenSSL vector)", () async {
    // x: our private value; y: the service's public value; the shared
    // secret has a leading zero byte, so the left-padding to 128 bytes is
    // exercised. ct = AES-128-CBC(key, iv, "vommet dh known answer").
    final x =
        _hex("efdbfb7517047d17faa55475c1afc497669db8943a6931eba0fffd2efd51855f"
            "268d45995cccb8c5fa1338f6c62f9ab0cf278c96a7c5be6e198be25079cba469"
            "8ee1be870250773540bf113d21c1e16846202aedf0e171f287961afb85f873ba"
            "5c81c108473c3adc8f2e494274025c14b4d4628afa35e4948cab933ec5c980f3");
    final ourPublic =
        _hex("58fc703cca9b4975114147994e2ea3bd8122f47106689755b558aa65f5c95d92"
            "b8472cc2d2fbd66a955778248786faa3ef31c0c059f6f66aa6fa6975b3d6988b"
            "885a417883cb5cda325a9d044366f9438c0bb1cd138de993750db8d5bd607259"
            "147cdbc829d79222661350f0bcaf168656a7b6175a3ef7e8b5900f406839335d");
    final y =
        _hex("2abccedec482d6b4b5f9e4ad659d68ee553247e7d7343da3d0304feaea50a03f"
            "e212a4fb493b4993dba09297d079ec5e70de9f8e578a84fdc5ee2c97db9e694c"
            "eac13b1200b7ae1d515ed5fddd62c399daf6ca045b7cdf0923c54d9834939315"
            "530bb84093717c62fff08e37fa22e00c3682c14c369bb406f9b50cc912877d68");
    final iv = _hex("000102030405060708090a0b0c0d0e0f");
    final ct = _hex(
        "54ced976a695ccf6881d5f27bdd599b82a9e874c9cc65c777dfa18fbea8b6bad");

    final exchange = DhIetf1024Exchange(privateKey: x);
    expect(exchange.publicKey, ourPublic);
    final transport = await exchange.transport(y);
    expect(
        utf8.decode(await transport.decrypt(iv, ct)), "vommet dh known answer");

    // A degenerate public value is refused.
    expect(() => exchange.transport([1]), throwsArgumentError);
    // A value that isn't this session's doesn't decrypt.
    expect(() => transport.decrypt(iv, ct.sublist(0, 16)), throwsA(anything));
  });

  test("no Secret Service on the bus is unreachable, not empty", () async {
    await service.stop();
    expect(await store().availability(), StoreAvailability.unavailable);
    expect(await store().read(), isA<StoreUnreachable>());
    await expectLater(() => store().write(KeyHierarchy.newMasterKey()),
        throwsA(isA<KeyStoreException>()));
    service = FakeSecretService();
    await service.start(address);
  });

  // The CI hosts without a keyring take this path for real: the vault with
  // the real Secret Service store and the real key file, on a bus where
  // nothing owns org.freedesktop.secrets.
  test("no keyring at all: the vault keeps its key in the key file", () async {
    await service.stop();
    final dir = await Directory(p.join(Directory.current.path, ".dart_tool"))
        .createTemp("ss_fallback_test_");
    try {
      final keys = p.join(dir.path, "keys");
      final vault = KeyVault(
          keystoreFile: KeystoreFile(keys),
          fileStore: FileKeyStore(keys),
          preferredStores: [store()],
          allowCreate: true);
      final status = await vault.unlock();
      expect(status.state, VaultState.ready);
      expect(status.store, KeyStoreKind.file);
      expect(status.fileNoticeDue, isTrue);
      expect(status.fallbackReason, isNotNull);
      expect(File(p.join(keys, "master.key")).existsSync(), isTrue);
      await vault.idle();
      // A restart without a keyring finds the same key.
      final again = KeyVault(
          keystoreFile: KeystoreFile(keys),
          fileStore: FileKeyStore(keys),
          preferredStores: [store()],
          allowCreate: true);
      expect((await again.unlock()).state, VaultState.ready);
      expect(await again.mediaKey(), await vault.mediaKey());
      await again.idle();
    } finally {
      await dir.delete(recursive: true);
      service = FakeSecretService();
      await service.start(address);
    }
  });
}

List<int> _hex(String s) => [
      for (var i = 0; i < s.length; i += 2)
        int.parse(s.substring(i, i + 2), radix: 16)
    ];
