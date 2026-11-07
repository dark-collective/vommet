import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

/// Vommet: checks a minisign signature (https://jedisct1.github.io/minisign/),
/// the format the release's SHA256SUMS.minisig is in. Both the file
/// signature (prehashed "ED", or legacy "Ed") and the global signature over
/// the trusted comment have to hold.
class Minisign {
  /// [publicKey] is the base64 key line of a minisign .pub file,
  /// [signature] the whole .minisig file.
  static Future<bool> verify(
      {required String publicKey,
      required List<int> message,
      required String signature}) async {
    try {
      final pk = base64.decode(publicKey.trim());
      if (pk.length != 42 || pk[0] != 0x45 || pk[1] != 0x64) return false;

      final lines = const LineSplitter()
          .convert(signature)
          .where((l) => l.trim().isNotEmpty)
          .toList();
      if (lines.length < 4) return false;
      final sig = base64.decode(lines[1].trim());
      if (sig.length != 74) return false;
      if (!listEquals(sig.sublist(2, 10), pk.sublist(2, 10))) return false;

      final List<int> signed;
      if (sig[0] == 0x45 && sig[1] == 0x44) {
        signed = (await Blake2b().hash(message)).bytes;
      } else if (sig[0] == 0x45 && sig[1] == 0x64) {
        signed = message;
      } else {
        return false;
      }

      final ed = Ed25519();
      final key = SimplePublicKey(pk.sublist(10), type: KeyPairType.ed25519);
      final fileSig = sig.sublist(10);
      if (!await ed.verify(signed,
          signature: Signature(fileSig, publicKey: key))) {
        return false;
      }

      const prefix = "trusted comment: ";
      if (!lines[2].startsWith(prefix)) return false;
      final trusted = utf8.encode(lines[2].substring(prefix.length));
      final global = base64.decode(lines[3].trim());
      return await ed.verify([...fileSig, ...trusted],
          signature: Signature(global, publicKey: key));
    } on FormatException {
      return false;
    }
  }
}
