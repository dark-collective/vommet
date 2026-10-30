// Vommet: local data encryption, the master key in the Linux keyring
// through the freedesktop Secret Service D-Bus API (GNOME Keyring, KWallet
// 5.97+/KSecretD, KeePassXC). A Dart client on package:dbus, so there is no
// libsecret dependency: without a Secret Service the app still runs (the
// key file fallback).
//
// The item: label "Vommet local data key", attributes
// {app: im.nether.chat, kind: master-key-v1}, in the default collection; the
// value is the key in base64 (so `secret-tool lookup app im.nether.chat`
// shows something printable).
//
// The session is encrypted like libsecret's: "dh-ietf1024-sha256-aes128-cbc-
// pkcs7" (a Diffie-Hellman exchange in the 1024-bit IKE group 2, HKDF-SHA256
// to an AES-128 key, the secret AES-CBC encrypted with a fresh IV), so the
// key never crosses the session bus in the clear, where a bus monitor of the
// same user could log it. A service that doesn't offer it (it's optional in
// the spec) gets the "plain" session, which is no worse than the keyring's
// own unlocked collection: only processes of the same user can read the bus.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:commet/security/key_vault/key_hierarchy.dart';
import 'package:commet/security/key_vault/keystore_document.dart';
import 'package:commet/security/key_vault/master_key_store.dart';
import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:dbus/dbus.dart';

class SecretServiceKeyStore extends MasterKeyStore {
  SecretServiceKeyStore(
      {this.clientFactory,
      this.appId = "im.nether.chat",
      this.plainOnly = false});

  /// For tests: a client on a private bus.
  final DBusClient Function()? clientFactory;
  final String appId;

  /// For tests: never try the encrypted session.
  final bool plainOnly;

  /// The algorithm of the last session this store opened ("plain" or
  /// [DhIetf1024Exchange.algorithm]), for diagnostics and tests.
  String? get lastSessionAlgorithm => _lastAlgorithm;
  String? _lastAlgorithm;

  static const String _bus = "org.freedesktop.secrets";
  static const String _serviceIface = "org.freedesktop.Secret.Service";
  static const String _collectionIface = "org.freedesktop.Secret.Collection";
  static const String _itemIface = "org.freedesktop.Secret.Item";
  static const String _promptIface = "org.freedesktop.Secret.Prompt";
  static const String label = "Vommet local data key";

  static const Duration callTimeout = Duration(seconds: 10);
  static const Duration promptTimeout = Duration(seconds: 120);

  Map<String, String> get attributes => {
        "app": appId,
        "kind": "master-key-v1",
        "xdg:schema": "im.nether.chat.LocalDataKey",
      };

  @override
  KeyStoreKind get kind => KeyStoreKind.keyring;

  @override
  String get name => "Secret Service keyring";

  Future<T> _withClient<T>(Future<T> Function(_Session s) action) async {
    DBusClient? client;
    try {
      client = clientFactory?.call() ?? DBusClient.session();
      final service = DBusRemoteObject(client,
          name: _bus, path: DBusObjectPath("/org/freedesktop/secrets"));
      final (session, transport) = await _openSession(service);
      try {
        return await action(_Session(client, service, session, transport));
      } finally {
        transport?.dispose();
        try {
          await DBusRemoteObject(client, name: _bus, path: session).callMethod(
              "org.freedesktop.Secret.Session",
              "Close", []).timeout(callTimeout);
        } catch (_) {}
      }
    } finally {
      await client?.close();
    }
  }

  /// Opens an encrypted session, or a plain one when the service doesn't
  /// offer the encrypted algorithm (or [plainOnly], for tests). Returns the
  /// session and its transport (null: plain).
  Future<(DBusObjectPath, SecretTransport?)> _openSession(
      DBusRemoteObject service) async {
    if (!plainOnly) {
      final exchange = DhIetf1024Exchange();
      try {
        final opened = await service
            .callMethod(
                _serviceIface,
                "OpenSession",
                [
                  const DBusString(DhIetf1024Exchange.algorithm),
                  DBusVariant(DBusArray.byte(exchange.publicKey)),
                ],
                replySignature: DBusSignature("vo"))
            .timeout(callTimeout);
        final peer = Uint8List.fromList(
            opened.values[0].asVariant().asByteArray().toList());
        final session = opened.values[1].asObjectPath();
        final transport = await exchange.transport(peer);
        _lastAlgorithm = DhIetf1024Exchange.algorithm;
        return (session, transport);
      } on DBusMethodResponseException catch (e) {
        // No service at all: the plain session wouldn't fare better.
        if (e.errorName == "org.freedesktop.DBus.Error.ServiceUnknown" ||
            e.errorName == "org.freedesktop.DBus.Error.NameHasNoOwner") {
          rethrow;
        }
        // Not offered (org.freedesktop.DBus.Error.NotSupported, or another
        // error from a service that only knows "plain"): plain.
      } finally {
        exchange.dispose();
      }
    }
    final opened = await service
        .callMethod(_serviceIface, "OpenSession",
            [const DBusString("plain"), DBusVariant(const DBusString(""))],
            replySignature: DBusSignature("vo"))
        .timeout(callTimeout);
    _lastAlgorithm = "plain";
    return (opened.values[1].asObjectPath(), null);
  }

  @override
  Future<StoreAvailability> availability() async {
    try {
      return await _withClient((s) async {
        final collection = await s.defaultCollection();
        if (collection == null) return StoreAvailability.unavailable;
        return await s.isLocked(collection)
            ? StoreAvailability.locked
            : StoreAvailability.available;
      });
    } catch (_) {
      return StoreAvailability.unavailable;
    }
  }

  @override
  Future<StoreReadResult> read({bool interactive = false}) async {
    try {
      return await _withClient((s) async {
        final (unlocked, locked) = await s.search(attributes);
        var items = unlocked;
        if (items.isEmpty && locked.isNotEmpty) {
          if (!interactive) return const StoreLocked();
          if (!await s.unlock(locked)) return const StoreLocked();
          items = locked;
        }
        if (items.isEmpty) {
          // Nothing found; a locked collection may hide it on some
          // implementations, so unlock it once when allowed.
          final collection = await s.defaultCollection();
          if (collection != null && await s.isLocked(collection)) {
            if (!interactive) return const StoreLocked();
            if (!await s.unlock([collection])) return const StoreLocked();
            final (again, _) = await s.search(attributes);
            items = again;
          }
        }
        if (items.isEmpty) return const StoreEmpty();
        final secret = await s.secret(items.first);
        if (secret == null) return const StoreEmpty();
        try {
          return StoreFound(Uint8List.fromList(base64.decode(secret)));
        } on FormatException {
          return const StoreNotAKey("the keyring item isn't a key");
        }
      });
    } on DBusMethodResponseException catch (e) {
      return StoreUnreachable("Secret Service error: ${_errorName(e)}");
    } on TimeoutException {
      return const StoreUnreachable("the Secret Service didn't answer");
    } catch (e) {
      return StoreUnreachable("no Secret Service: ${e.runtimeType}");
    }
  }

  @override
  Future<void> write(Uint8List key) async {
    try {
      await _withClient((s) async {
        final collection = await s.defaultCollection();
        if (collection == null) {
          throw KeyStoreException("there is no default keyring");
        }
        if (await s.isLocked(collection)) {
          throw KeyStoreException("the keyring is locked", locked: true);
        }
        final value = utf8.encode(base64.encode(key));
        try {
          await s.createItem(collection, label, attributes, value,
              replace: true);
        } finally {
          value.fillRange(0, value.length, 0);
        }
      });
    } on KeyStoreException {
      rethrow;
    } on DBusMethodResponseException catch (e) {
      throw KeyStoreException("Secret Service error: ${_errorName(e)}");
    } on TimeoutException {
      throw KeyStoreException("the Secret Service didn't answer");
    } catch (e) {
      throw KeyStoreException("no Secret Service: ${e.runtimeType}");
    }
  }

  /// The attributes of an item [archive] set aside: another `kind`, so a
  /// search for [attributes] (which matches any item that has at least
  /// those) never finds it.
  Map<String, String> archivedAttributes(String when) => {
        ...attributes,
        "kind": "master-key-v1-archived",
        "archived": when,
      };

  /// Keeps each item holding a key as an archived copy (new attributes,
  /// same secret), then deletes the original: a key a new one replaces is
  /// never lost (`secret-tool search app im.nether.chat` lists both).
  @override
  Future<void> archive() async {
    try {
      await _withClient((s) async {
        final collection = await s.defaultCollection();
        if (collection == null) {
          throw KeyStoreException("there is no default keyring");
        }
        if (await s.isLocked(collection)) {
          throw KeyStoreException("the keyring is locked", locked: true);
        }
        final (unlocked, locked) = await s.search(attributes);
        if (locked.isNotEmpty) {
          throw KeyStoreException("the keyring is locked", locked: true);
        }
        for (final item in unlocked) {
          final secret = await s.secret(item);
          if (secret == null) {
            throw KeyStoreException("the keyring item can't be read");
          }
          final value = utf8.encode(secret);
          final when = DateTime.now().toUtc().toIso8601String();
          try {
            await s.createItem(collection, "$label (set aside $when)",
                archivedAttributes(when), value,
                replace: false);
          } finally {
            value.fillRange(0, value.length, 0);
          }
          await s.deleteItem(item);
        }
      });
    } on KeyStoreException {
      rethrow;
    } on DBusMethodResponseException catch (e) {
      throw KeyStoreException("Secret Service error: ${_errorName(e)}");
    } on TimeoutException {
      throw KeyStoreException("the Secret Service didn't answer");
    } catch (e) {
      throw KeyStoreException("no Secret Service: ${e.runtimeType}");
    }
  }

  /// The keys of archived items (unlocked ones only: never prompts). They
  /// are never pruned here: they are in the keyring, listed as "set aside"
  /// items (`secret-tool search app im.nether.chat kind
  /// master-key-v1-archived`), and the user removes them there.
  @override
  Future<List<Uint8List>> archivedKeys() async {
    try {
      return await _withClient((s) async {
        final (unlocked, _) = await s
            .search({"app": appId, "kind": archivedAttributes("")["kind"]!});
        final keys = <Uint8List>[];
        for (final item in unlocked) {
          try {
            final secret = await s.secret(item);
            if (secret == null) continue;
            final key = Uint8List.fromList(base64.decode(secret));
            if (key.length == KeyHierarchy.keyLength) keys.add(key);
          } catch (_) {}
        }
        return keys;
      });
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> delete() async {
    try {
      await _withClient((s) async {
        final (unlocked, locked) = await s.search(attributes);
        for (final item in [...unlocked, ...locked]) {
          await s.deleteItem(item);
        }
      });
    } on DBusMethodResponseException catch (e) {
      throw KeyStoreException("Secret Service error: ${_errorName(e)}");
    } on TimeoutException {
      throw KeyStoreException("the Secret Service didn't answer");
    } catch (e) {
      throw KeyStoreException("no Secret Service: ${e.runtimeType}");
    }
  }

  static String _errorName(DBusMethodResponseException e) =>
      e.response.errorName;
}

class _Session {
  _Session(this.client, this.service, this.session, this.transport);

  final DBusClient client;
  final DBusRemoteObject service;
  final DBusObjectPath session;

  /// The encrypted session's cipher; null for a plain session.
  final SecretTransport? transport;

  /// A secret value as sent: (parameters, value).
  Future<(List<int>, List<int>)> seal(List<int> value) async {
    final t = transport;
    if (t == null) return (const <int>[], List<int>.of(value));
    return t.encrypt(value);
  }

  static const _timeout = SecretServiceKeyStore.callTimeout;

  Future<DBusObjectPath?> defaultCollection() async {
    final result = await service
        .callMethod(SecretServiceKeyStore._serviceIface, "ReadAlias",
            [const DBusString("default")],
            replySignature: DBusSignature("o"))
        .timeout(_timeout);
    final path = result.values[0].asObjectPath();
    return path.value == "/" ? null : path;
  }

  Future<bool> isLocked(DBusObjectPath collection) async {
    final value = await DBusRemoteObject(client,
            name: SecretServiceKeyStore._bus, path: collection)
        .getProperty(SecretServiceKeyStore._collectionIface, "Locked",
            signature: DBusSignature("b"))
        .timeout(_timeout);
    return value.asBoolean();
  }

  Future<(List<DBusObjectPath>, List<DBusObjectPath>)> search(
      Map<String, String> attributes) async {
    final result = await service
        .callMethod(
            SecretServiceKeyStore._serviceIface,
            "SearchItems",
            [
              DBusDict(
                  DBusSignature("s"),
                  DBusSignature("s"),
                  attributes
                      .map((k, v) => MapEntry(DBusString(k), DBusString(v)))),
            ],
            replySignature: DBusSignature("aoao"))
        .timeout(_timeout);
    return (
      result.values[0].asObjectPathArray().toList(),
      result.values[1].asObjectPathArray().toList(),
    );
  }

  /// Unlocks [objects]; true when they are unlocked afterwards.
  Future<bool> unlock(List<DBusObjectPath> objects) async {
    final result = await service
        .callMethod(SecretServiceKeyStore._serviceIface, "Unlock",
            [DBusArray.objectPath(objects)],
            replySignature: DBusSignature("aoo"))
        .timeout(_timeout);
    if (result.values[0].asObjectPathArray().isNotEmpty) return true;
    final prompt = result.values[1].asObjectPath();
    if (prompt.value == "/") return false;
    final completed = await this.prompt(prompt);
    return completed != null;
  }

  /// Shows a keyring prompt; the prompt's result, or null when it was
  /// dismissed or timed out.
  Future<DBusValue?> prompt(DBusObjectPath path) async {
    final object =
        DBusRemoteObject(client, name: SecretServiceKeyStore._bus, path: path);
    final signals = DBusRemoteObjectSignalStream(
        object: object,
        interface: SecretServiceKeyStore._promptIface,
        name: "Completed",
        signature: DBusSignature("bv"));
    final completer = Completer<DBusValue?>();
    final subscription = signals.listen((signal) {
      if (completer.isCompleted) return;
      final dismissed = signal.values[0].asBoolean();
      completer.complete(dismissed ? null : signal.values[1].asVariant());
    });
    try {
      await object
          .callMethod(SecretServiceKeyStore._promptIface, "Prompt",
              [const DBusString("")],
              replySignature: DBusSignature(""))
          .timeout(_timeout);
      return await completer.future.timeout(SecretServiceKeyStore.promptTimeout,
          onTimeout: () {
        object.callMethod(
            SecretServiceKeyStore._promptIface, "Dismiss", []).ignore();
        return null;
      });
    } finally {
      await subscription.cancel();
    }
  }

  /// Creates an item in [collection] holding [value]; with [replace], one
  /// with the same attributes is replaced. Throws [KeyStoreException] when
  /// the prompt is dismissed.
  Future<void> createItem(DBusObjectPath collection, String label,
      Map<String, String> attributes, List<int> value,
      {required bool replace}) async {
    final (parameters, sealed) = await seal(value);
    try {
      final created = await DBusRemoteObject(client,
              name: SecretServiceKeyStore._bus, path: collection)
          .callMethod(
              SecretServiceKeyStore._collectionIface,
              "CreateItem",
              [
                DBusDict.stringVariant({
                  "${SecretServiceKeyStore._itemIface}.Label":
                      DBusString(label),
                  "${SecretServiceKeyStore._itemIface}.Attributes": DBusDict(
                      DBusSignature("s"),
                      DBusSignature("s"),
                      attributes.map(
                          (k, v) => MapEntry(DBusString(k), DBusString(v)))),
                }),
                DBusStruct([
                  session,
                  DBusArray.byte(parameters),
                  DBusArray.byte(sealed),
                  const DBusString("text/plain"),
                ]),
                DBusBoolean(replace),
              ],
              replySignature: DBusSignature("oo"))
          .timeout(_timeout);
      final prompt = created.values[1].asObjectPath();
      if (prompt.value != "/") {
        final result = await this.prompt(prompt);
        if (result == null) {
          throw KeyStoreException("the keyring prompt was dismissed");
        }
      }
    } finally {
      sealed.fillRange(0, sealed.length, 0);
    }
  }

  /// Deletes [item] (through a prompt when the service asks for one).
  Future<void> deleteItem(DBusObjectPath item) async {
    final result = await DBusRemoteObject(client,
            name: SecretServiceKeyStore._bus, path: item)
        .callMethod(SecretServiceKeyStore._itemIface, "Delete", [],
            replySignature: DBusSignature("o"))
        .timeout(_timeout);
    final prompt = result.values[0].asObjectPath();
    if (prompt.value != "/") await this.prompt(prompt);
  }

  /// The item's secret as text, or null when it has none.
  Future<String?> secret(DBusObjectPath item) async {
    final result = await service
        .callMethod(
            SecretServiceKeyStore._serviceIface,
            "GetSecrets",
            [
              DBusArray.objectPath([item]),
              session
            ],
            replySignature: DBusSignature("a{o(oayays)}"))
        .timeout(_timeout);
    final secrets = result.values[0].asDict();
    final entry = secrets[item];
    if (entry == null) return null;
    final fields = entry.asStruct();
    final parameters = fields[1].asByteArray().toList();
    var bytes = Uint8List.fromList(fields[2].asByteArray().toList());
    final t = transport;
    if (t != null) {
      final sealed = bytes;
      try {
        bytes = await t.decrypt(parameters, sealed);
      } on SecretBoxPaddingError {
        return null;
      } on ArgumentError {
        return null;
      } finally {
        sealed.fillRange(0, sealed.length, 0);
      }
    }
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return null;
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }
}

/// The encrypted session's cipher: AES-128-CBC with PKCS#7 padding under the
/// key both sides derived, a fresh 16-byte IV per secret (the "parameters").
class SecretTransport {
  SecretTransport(this._key);

  final Uint8List _key;
  static const _cipher =
      DartAesCbc.with128bits(macAlgorithm: MacAlgorithm.empty);

  Future<(List<int>, List<int>)> encrypt(List<int> value) async {
    final iv = KeyHierarchy.randomBytes(16);
    final box =
        await _cipher.encrypt(value, secretKey: SecretKeyData(_key), nonce: iv);
    return (iv, box.cipherText);
  }

  /// Throws [ArgumentError] or [SecretBoxPaddingError]
  /// when [sealed] isn't a value of this session.
  Future<Uint8List> decrypt(List<int> parameters, List<int> sealed) async {
    if (parameters.length != 16 || sealed.isEmpty || sealed.length % 16 != 0) {
      throw ArgumentError("not a secret of this session");
    }
    final clear = await _cipher.decrypt(
        SecretBox(sealed, nonce: parameters, mac: Mac.empty),
        secretKey: SecretKeyData(_key));
    return Uint8List.fromList(clear);
  }

  void dispose() => _key.fillRange(0, _key.length, 0);
}

/// The client side of "dh-ietf1024-sha256-aes128-cbc-pkcs7", as libsecret
/// and gnome-keyring do it: Diffie-Hellman in the RFC 2409 second Oakley
/// group (1024-bit MODP, generator 2), the shared secret as a big-endian
/// number left-padded with zeros to the prime's 128 bytes, then HKDF-SHA256
/// with no salt and no info to a 16-byte AES key.
class DhIetf1024Exchange {
  /// [privateKey] is for known-answer tests; normally 128 random bytes.
  DhIetf1024Exchange({List<int>? privateKey})
      : _private = _bigInt(privateKey ?? KeyHierarchy.randomBytes(128)) {
    publicKey = _bytes(generator.modPow(_private, prime));
  }

  static const String algorithm = "dh-ietf1024-sha256-aes128-cbc-pkcs7";

  static final BigInt prime = BigInt.parse(
      "FFFFFFFFFFFFFFFFC90FDAA22168C234C4C6628B80DC1CD1"
      "29024E088A67CC74020BBEA63B139B22514A08798E3404DD"
      "EF9519B3CD3A431B302B0A6DF25F14374FE1356D6D51C245"
      "E485B576625E7EC6F44C42E9A637ED6B0BFF5CB6F406B7ED"
      "EE386BFB5A899FA5AE9F24117C4B1FE649286651ECE65381"
      "FFFFFFFFFFFFFFFF",
      radix: 16);
  static final BigInt generator = BigInt.two;
  static const int primeLength = 128;

  BigInt _private;

  /// Our public value, big-endian without leading zeros (as libsecret sends
  /// it).
  late final Uint8List publicKey;

  /// The session cipher for the service's public value [peer]. Throws
  /// [ArgumentError] for a value outside 2..p-2 (which would make the
  /// shared secret guessable).
  Future<SecretTransport> transport(List<int> peer) async {
    final y = _bigInt(peer);
    if (y <= BigInt.one || y >= prime - BigInt.one) {
      throw ArgumentError("the Secret Service sent an invalid public value");
    }
    final shared = _bytes(y.modPow(_private, prime), length: primeLength);
    try {
      final derived =
          await const DartHkdf(hmac: DartHmac(DartSha256()), outputLength: 16)
              .deriveKey(secretKey: SecretKeyData(shared));
      return SecretTransport(Uint8List.fromList(await derived.extractBytes()));
    } finally {
      shared.fillRange(0, shared.length, 0);
    }
  }

  void dispose() => _private = BigInt.zero;

  static BigInt _bigInt(List<int> bytes) {
    var v = BigInt.zero;
    for (final b in bytes) {
      v = (v << 8) | BigInt.from(b);
    }
    return v;
  }

  /// Big-endian; [length] left-pads with zeros (else minimal, at least 1).
  static Uint8List _bytes(BigInt v, {int? length}) {
    final out = <int>[];
    var x = v;
    while (x > BigInt.zero) {
      out.add((x & BigInt.from(0xff)).toInt());
      x = x >> 8;
    }
    if (out.isEmpty) out.add(0);
    while (length != null && out.length < length) {
      out.add(0);
    }
    return Uint8List.fromList(out.reversed.toList());
  }
}
