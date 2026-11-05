// Vommet issue 1070: account data lives on the server before its sync echo.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:commet/client/matrix/drafts/encrypted_draft_store.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:pointycastle/export.dart' as pc;

/// Pure-Dart SSSS construction for deterministic unit tests without native FFI.
/// It deliberately mimics the SDK's byte-to-character decrypt conversion.
/// Real SDK crypto is separately exercised by the homeserver integration test.
class DraftTestCipher extends DraftCipher {
  final sealed = <String>[];
  int opens = 0;
  Completer<void>? holdSeal;

  (Uint8List, Uint8List) keys(Uint8List key, String type) {
    final prk = crypto.Hmac(crypto.sha256, Uint8List(32)).convert(key).bytes;
    final a = crypto.Hmac(
      crypto.sha256,
      prk,
    ).convert([...utf8.encode(type), 1]).bytes;
    final b = crypto.Hmac(
      crypto.sha256,
      prk,
    ).convert([...a, ...utf8.encode(type), 2]).bytes;
    return (Uint8List.fromList(a), Uint8List.fromList(b));
  }

  Uint8List crypt(Uint8List key, Uint8List iv, Uint8List bytes) =>
      (pc.CTRStreamCipher(pc.AESEngine())
            ..init(true, pc.ParametersWithIV(pc.KeyParameter(key), iv)))
          .process(bytes);

  @override
  Future<EncryptedContent> seal(
    String plain,
    Uint8List key,
    String type,
  ) async {
    sealed.add(plain);
    await holdSeal?.future;
    final (a, b) = keys(key, type);
    final iv = Uint8List(16); // Test vector only; SDK production IV is random.
    final ciphertext = crypt(a, iv, Uint8List.fromList(utf8.encode(plain)));
    return EncryptedContent(
      iv: base64.encode(iv),
      ciphertext: base64.encode(ciphertext),
      mac: base64.encode(
        crypto.Hmac(crypto.sha256, b).convert(ciphertext).bytes,
      ),
    );
  }

  @override
  Future<String> open(EncryptedContent data, Uint8List key, String type) async {
    opens++;
    final (a, b) = keys(key, type);
    final ct = base64.decode(data.ciphertext);
    if (base64.encode(crypto.Hmac(crypto.sha256, b).convert(ct).bytes) !=
        data.mac) {
      throw const FormatException('Bad MAC');
    }
    return String.fromCharCodes(crypt(a, base64.decode(data.iv), ct));
  }
}

class DraftServer {
  final events = <String, Map<String, Object?>>{};
  String keyId = 'key-one';
  Completer<void>? holdWrite;
  bool rejectWrite = false;
  int writes = 0;
}

class DraftSdk extends Fake implements matrix.Client {
  DraftSdk(this.server, this.deviceID, {this.userID = '@me:example.org'});
  final DraftServer server;
  @override
  final String deviceID;
  @override
  final String userID;
  @override
  Uri get homeserver => Uri.https('example.org');
  @override
  final accountData = <String, matrix.BasicEvent>{};
  @override
  final onSync = CachedStreamController<matrix.SyncUpdate>();
  @override
  final onLoginStateChanged = CachedStreamController<matrix.LoginState>();
  @override
  bool isLogged() => true;
  String key(String user, String type) => '$user\u0000$type';

  @override
  Future<Map<String, Object?>> getAccountData(String user, String type) async {
    if (type == matrix.EventTypes.SecretStorageDefaultKey)
      return {'key': server.keyId};
    final value = server.events[key(user, type)];
    if (value == null)
      throw matrix.MatrixException(
          http.Response('{"errcode":"M_NOT_FOUND"}', 404));
    return Map<String, Object?>.from(jsonDecode(jsonEncode(value)) as Map);
  }

  @override
  Future<void> setAccountData(
    String user,
    String type,
    Map<String, Object?> content,
  ) async {
    server.writes++;
    await server.holdWrite?.future;
    if (server.rejectWrite) throw StateError('Test offline');
    server.events[key(user, type)] = Map<String, Object?>.from(
      jsonDecode(jsonEncode(content)) as Map,
    );
  }

  void echo(String type, Map<String, Object?> content) {
    final event = matrix.BasicEvent(type: type, content: content);
    accountData[type] = event;
    onSync.add(matrix.SyncUpdate(nextBatch: 'fixture', accountData: [event]));
  }

  Future<void> syncFromServer() async {
    for (final entry in server.events.entries.where(
      (e) => e.key.startsWith('$userID\u0000'),
    )) {
      echo(entry.key.substring(userID.length + 1), entry.value);
    }
    await Future<void>.delayed(Duration.zero);
  }
}

class _Secrets extends Fake implements SSSS {
  _Secrets(this.client);
  @override
  final matrix.Client client;
}

class DraftHandle extends Fake implements OpenSSSS {
  DraftHandle(matrix.Client client, this.keyId, [int seed = 7])
      : ssss = _Secrets(client),
        privateKey = Uint8List.fromList(List.filled(32, seed));
  @override
  final SSSS ssss;
  @override
  final String keyId;
  @override
  final Uint8List privateKey;
  @override
  bool get isUnlocked => true;
}
