// Vommet: local data encryption, the master key under Flatpak through the
// Secret portal (org.freedesktop.portal.Secret). The portal hands the app a
// secret of its own (kept by the host keyring, per app id); the master key is
// wrapped with a key derived from it (XChaCha20-Poly1305) and the wrapped
// copy is kept in keys/master.wrapped ("VPW1" + nonce + ciphertext + MAC).
// The portal works without --talk-name=org.freedesktop.secrets, which is why
// Flatpak prefers it.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:commet/security/key_vault/key_file_io.dart';
import 'package:commet/security/key_vault/key_hierarchy.dart';
import 'package:commet/security/key_vault/keystore_document.dart';
import 'package:commet/security/key_vault/master_key_store.dart';
import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:dbus/dbus.dart';
import 'package:path/path.dart' as p;

/// Gets the app's portal secret. Replaceable in tests.
typedef PortalSecretSource = Future<Uint8List> Function();

class PortalKeyStore extends MasterKeyStore {
  PortalKeyStore(String keysDirectory, {PortalSecretSource? secretSource})
      : _file = KeyFileIo(p.join(keysDirectory, fileName), _magic),
        _secretSource = secretSource ?? retrievePortalSecret;

  static const String fileName = "master.wrapped";
  static const List<int> _magic = [0x56, 0x50, 0x57, 0x31]; // "VPW1"
  static const int _nonceLength = 24;
  static const int _macLength = 16;
  static final List<int> _aad = utf8.encode("vommet master key v1");

  static const Duration timeout = Duration(seconds: 30);

  final KeyFileIo _file;
  final PortalSecretSource _secretSource;

  static final _cipher = DartXchacha20.poly1305Aead();
  static final _hkdf = DartHkdf(hmac: DartHmac.sha256(), outputLength: 32);

  /// Whether this process runs as a Flatpak.
  static bool get inFlatpak =>
      Platform.environment.containsKey("FLATPAK_ID") ||
      File("/.flatpak-info").existsSync();

  @override
  KeyStoreKind get kind => KeyStoreKind.portal;

  @override
  String get name => "Secret portal";

  Future<SecretKey> _kek() async {
    final secret = await _secretSource().timeout(timeout);
    if (secret.length < 16) {
      throw KeyStoreException("the Secret portal returned no secret");
    }
    try {
      return await _hkdf.deriveKey(
          secretKey: SecretKeyData(secret),
          nonce: const [],
          info: utf8.encode(KeyHierarchy.portalKekInfo));
    } finally {
      secret.fillRange(0, secret.length, 0);
    }
  }

  @override
  Future<StoreAvailability> availability() async {
    try {
      await _kek();
      return StoreAvailability.available;
    } catch (_) {
      return StoreAvailability.unavailable;
    }
  }

  @override
  Future<StoreReadResult> read({bool interactive = false}) async {
    final Uint8List? wrapped;
    try {
      wrapped = await _file.read();
    } on FileSystemException catch (e) {
      return StoreUnreachable("can't read the wrapped key: ${e.message}");
    } on FormatException {
      return const StoreNotAKey("the wrapped key file is damaged");
    }
    if (wrapped == null) return const StoreEmpty();
    if (wrapped.length != _nonceLength + KeyHierarchy.keyLength + _macLength) {
      return const StoreNotAKey("the wrapped key file is damaged");
    }
    final SecretKey kek;
    try {
      kek = await _kek();
    } on KeyStoreException catch (e) {
      return StoreUnreachable(e.reason);
    } on TimeoutException {
      return const StoreUnreachable("the Secret portal didn't answer");
    } catch (e) {
      return StoreUnreachable("no Secret portal: ${e.runtimeType}");
    }
    try {
      final box = SecretBox(
          Uint8List.sublistView(
              wrapped, _nonceLength, _nonceLength + KeyHierarchy.keyLength),
          nonce: Uint8List.sublistView(wrapped, 0, _nonceLength),
          mac: Mac(Uint8List.sublistView(
              wrapped, _nonceLength + KeyHierarchy.keyLength)));
      final key = await _cipher.decrypt(box, secretKey: kek, aad: _aad);
      return StoreFound(Uint8List.fromList(key));
    } on SecretBoxAuthenticationError {
      // The portal's secret changed (the host keyring was reset): this
      // store no longer has the key.
      return const StoreEmpty();
    }
  }

  @override
  Future<void> write(Uint8List key) async {
    final SecretKey kek;
    try {
      kek = await _kek();
    } on KeyStoreException {
      rethrow;
    } on TimeoutException {
      throw KeyStoreException("the Secret portal didn't answer");
    } catch (e) {
      throw KeyStoreException("no Secret portal: ${e.runtimeType}");
    }
    final box = await _cipher.encrypt(key,
        secretKey: kek,
        nonce: KeyHierarchy.randomBytes(_nonceLength),
        aad: _aad);
    try {
      await _file.write([...box.nonce, ...box.cipherText, ...box.mac.bytes]);
    } on FileSystemException catch (e) {
      throw KeyStoreException("can't write the wrapped key: ${e.message}");
    } on KeyFileNotPrivate {
      throw KeyStoreException(
          "the wrapped key can't be made readable by this user only");
    }
  }

  @override
  Future<void> archive() async {
    try {
      await _file.archive();
    } on FileSystemException catch (e) {
      throw KeyStoreException("can't set the wrapped key aside: ${e.message}");
    }
  }

  @override
  Future<List<Uint8List>> archivedKeys() async {
    final archives = await _file.readArchives();
    if (archives.isEmpty) return const [];
    final SecretKey kek;
    try {
      kek = await _kek();
    } catch (_) {
      return const [];
    }
    final keys = <Uint8List>[];
    for (final wrapped in archives) {
      if (wrapped.length !=
          _nonceLength + KeyHierarchy.keyLength + _macLength) {
        continue;
      }
      try {
        final box = SecretBox(
            Uint8List.sublistView(
                wrapped, _nonceLength, _nonceLength + KeyHierarchy.keyLength),
            nonce: Uint8List.sublistView(wrapped, 0, _nonceLength),
            mac: Mac(Uint8List.sublistView(
                wrapped, _nonceLength + KeyHierarchy.keyLength)));
        keys.add(Uint8List.fromList(
            await _cipher.decrypt(box, secretKey: kek, aad: _aad)));
      } catch (_) {}
    }
    return keys;
  }

  @override
  Future<void> pruneArchives({int keep = MasterKeyStore.archivesKept}) =>
      _file.pruneArchives(keep);

  @override
  Future<void> delete() async {
    try {
      await _file.delete();
    } on FileSystemException catch (e) {
      throw KeyStoreException("can't delete the wrapped key: ${e.message}");
    }
  }

  /// org.freedesktop.portal.Secret.RetrieveSecret: the portal writes the
  /// app's secret into a pipe and answers on a Request object.
  static Future<Uint8List> retrievePortalSecret({DBusClient? bus}) async {
    final client = bus ?? DBusClient.session();
    final pipe = await Pipe.create();
    StreamSubscription<DBusSignal>? subscription;
    try {
      await client.ping();
      final sender =
          client.uniqueName.replaceFirst(":", "").replaceAll(".", "_");
      final token = "vommet${KeyHierarchy.hex(KeyHierarchy.randomBytes(6))}";
      final request = DBusRemoteObject(client,
          name: "org.freedesktop.portal.Desktop",
          path: DBusObjectPath(
              "/org/freedesktop/portal/desktop/request/$sender/$token"));
      final response = Completer<int>();
      subscription = DBusRemoteObjectSignalStream(
              object: request,
              interface: "org.freedesktop.portal.Request",
              name: "Response",
              signature: DBusSignature("ua{sv}"))
          .listen((signal) {
        if (!response.isCompleted) {
          response.complete(signal.values[0].asUint32());
        }
      });
      // Let the match rule reach the bus before the call.
      await client.ping();

      final reading = pipe.read.fold<BytesBuilder>(
          BytesBuilder(copy: false), (b, chunk) => b..add(chunk));
      await DBusRemoteObject(client,
              name: "org.freedesktop.portal.Desktop",
              path: DBusObjectPath("/org/freedesktop/portal/desktop"))
          .callMethod(
              "org.freedesktop.portal.Secret",
              "RetrieveSecret",
              [
                DBusUnixFd(ResourceHandle.fromWritePipe(pipe.write)),
                DBusDict.stringVariant({"handle_token": DBusString(token)}),
              ],
              replySignature: DBusSignature("o"))
          .timeout(timeout);
      // The portal has its own copy of the write end now.
      await pipe.write.close();

      final code = await response.future.timeout(timeout);
      if (code != 0) {
        throw KeyStoreException("the Secret portal refused (response $code)");
      }
      final bytes = (await reading.timeout(timeout)).takeBytes();
      return bytes;
    } finally {
      await subscription?.cancel();
      try {
        await pipe.write.close();
      } catch (_) {}
      if (bus == null) await client.close();
    }
  }
}
