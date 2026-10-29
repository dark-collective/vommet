// Vommet: the Matrix key export file ("MEGOLM SESSION DATA"), as specified in
// the client-server spec, "Key exports". The same format Element, Cinny and
// other Matrix apps write, so a file moves keys between them.
//
// Layout of the decoded file: 0x01 | salt (16) | IV (16) | rounds (u32 BE) |
// AES-256-CTR ciphertext | HMAC-SHA-256 over everything before it. The AES
// and HMAC keys are the two halves of PBKDF2-HMAC-SHA-512(passphrase, salt,
// rounds, 512 bits). The plaintext is a JSON array of exported sessions.
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

class KeyFileException implements Exception {
  const KeyFileException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// The MAC didn't match: a wrong passphrase, or a damaged file.
class WrongPassphraseException extends KeyFileException {
  const WrongPassphraseException()
      : super("Wrong passphrase, or the file is damaged");
}

class MegolmKeyFile {
  static const header = "-----BEGIN MEGOLM SESSION DATA-----";
  static const footer = "-----END MEGOLM SESSION DATA-----";

  /// What Element uses; a few seconds of PBKDF2 on a phone.
  static const defaultRounds = 500000;

  /// The most rounds an imported file may ask for. Element Web and Element
  /// Android write 500,000 and matrix-rust-sdk suggests about 100,000, so
  /// 10 million (20 times Element) accepts every real file, while a crafted
  /// one can't ask for 2^32 rounds and keep the import busy for hours.
  static const maxRounds = 10000000;

  static const _version = 1;
  static const _lineLength = 96;

  /// Encrypts [sessions] into the armored text of a key file. Runs in a
  /// background isolate (PBKDF2 is deliberately slow).
  static Future<String> encrypt(
    List<Map<String, dynamic>> sessions,
    String passphrase, {
    int rounds = defaultRounds,
  }) {
    final payload = utf8.encode(jsonEncode(sessions));
    return compute(_encryptArgs, (payload, passphrase, rounds));
  }

  /// Decrypts the armored text of a key file into its exported sessions.
  /// Throws [WrongPassphraseException] or [KeyFileException].
  static Future<List<Map<String, dynamic>>> decrypt(
    String file,
    String passphrase,
  ) {
    return compute(_decryptArgs, (file, passphrase));
  }

  static Future<String> _encryptArgs((Uint8List, String, int) a) =>
      encryptSync(a.$1, a.$2, a.$3);

  static Future<List<Map<String, dynamic>>> _decryptArgs((String, String) a) =>
      decryptSync(a.$1, a.$2);

  /// [encrypt] on the calling isolate; [salt] and [iv] are for tests.
  static Future<String> encryptSync(
    Uint8List payload,
    String passphrase,
    int rounds, {
    Uint8List? salt,
    Uint8List? iv,
  }) async {
    final rng = Random.secure();
    salt ??= Uint8List.fromList(List.generate(16, (_) => rng.nextInt(256)));
    iv ??= Uint8List.fromList(List.generate(16, (_) => rng.nextInt(256)));
    // Clear bit 63 so the 64-bit counter can't overflow (spec).
    iv[8] &= 0x7f;

    final (aesKey, macKey) = await _deriveKeys(passphrase, salt, rounds);
    final box = await AesCtr.with256bits(
      macAlgorithm: MacAlgorithm.empty,
    ).encrypt(payload, secretKey: aesKey, nonce: iv);

    final body = BytesBuilder(copy: false)
      ..addByte(_version)
      ..add(salt)
      ..add(iv)
      ..add(_u32(rounds))
      ..add(box.cipherText);
    final unsigned = body.toBytes();
    final mac = await Hmac.sha256().calculateMac(unsigned, secretKey: macKey);

    final b64 = base64.encode([...unsigned, ...mac.bytes]);
    final lines = <String>[header];
    for (var i = 0; i < b64.length; i += _lineLength) {
      lines.add(b64.substring(i, min(i + _lineLength, b64.length)));
    }
    lines.add(footer);
    return "${lines.join("\n")}\n";
  }

  /// [decrypt] on the calling isolate.
  static Future<List<Map<String, dynamic>>> decryptSync(
    String file,
    String passphrase,
  ) async {
    final data = _unarmor(file);
    // version + salt + IV + rounds + (at least 0 bytes) + MAC
    if (data.length < 1 + 16 + 16 + 4 + 32) {
      throw const KeyFileException("The key file is too short");
    }
    if (data[0] != _version) {
      throw KeyFileException("Unsupported key file version ${data[0]}");
    }
    final salt = data.sublist(1, 17);
    final iv = data.sublist(17, 33);
    final rounds = ByteData.sublistView(data, 33, 37).getUint32(0);
    if (rounds < 1) {
      throw const KeyFileException("The key file is damaged");
    }
    // The round count comes from the file; check it before deriving.
    if (rounds > maxRounds) {
      throw const KeyFileException(
          "The key file asks for too many rounds (over 10 million)");
    }
    final macStart = data.length - 32;
    final cipherText = data.sublist(37, macStart);

    final (aesKey, macKey) = await _deriveKeys(passphrase, salt, rounds);
    final mac = await Hmac.sha256().calculateMac(
      data.sublist(0, macStart),
      secretKey: macKey,
    );
    if (!_constantTimeEquals(mac.bytes, data.sublist(macStart))) {
      throw const WrongPassphraseException();
    }

    final plain =
        await AesCtr.with256bits(macAlgorithm: MacAlgorithm.empty).decrypt(
      SecretBox(cipherText, nonce: iv, mac: Mac.empty),
      secretKey: aesKey,
    );

    final Object? json;
    try {
      json = jsonDecode(utf8.decode(plain));
    } on FormatException {
      throw const KeyFileException("The key file's contents aren't readable");
    }
    if (json is! List) {
      throw const KeyFileException("The key file's contents aren't readable");
    }
    return [
      for (final s in json)
        if (s is Map) Map<String, dynamic>.from(s),
    ];
  }

  /// True if [text] looks like a key file (has the header line).
  static bool looksLikeKeyFile(String text) => text.contains(header);

  static Uint8List _unarmor(String file) {
    final start = file.indexOf(header);
    final end = file.indexOf(footer);
    if (start < 0 || end < 0 || end < start) {
      throw const KeyFileException("This isn't a Matrix key file");
    }
    final b64 = file
        .substring(start + header.length, end)
        .replaceAll(RegExp(r"\s"), "");
    try {
      // Element writes it without '=' padding.
      return base64.decode(base64.normalize(b64));
    } on FormatException {
      throw const KeyFileException("The key file is damaged");
    }
  }

  static Future<(SecretKey, SecretKey)> _deriveKeys(
    String passphrase,
    List<int> salt,
    int rounds,
  ) async {
    final derived = await Pbkdf2(
      macAlgorithm: Hmac.sha512(),
      iterations: rounds,
      bits: 512,
    ).deriveKeyFromPassword(password: passphrase, nonce: salt);
    final bytes = await derived.extractBytes();
    return (SecretKey(bytes.sublist(0, 32)), SecretKey(bytes.sublist(32, 64)));
  }

  static Uint8List _u32(int v) =>
      Uint8List(4)..buffer.asByteData().setUint32(0, v);

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
