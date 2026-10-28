import 'dart:typed_data';

import 'package:commet/utils/recovery_key_guard.dart';
import 'package:matrix/encryption.dart';
import 'package:test/test.dart';

void main() {
  final key = SSSS.encodeRecoveryKey(
      Uint8List.fromList(List.generate(32, (i) => (i * 7 + 3) % 256)));

  test("spots a recovery key in groups of four", () {
    expect(RecoveryKeyGuard.containsRecoveryKey("here you go: $key thanks"),
        isTrue);
  });

  test("spots a recovery key pasted without spaces", () {
    expect(
        RecoveryKeyGuard.containsRecoveryKey(key.replaceAll(" ", "")), isTrue);
  });

  test("ignores a key with one character changed (parity)", () {
    final broken =
        key.substring(0, 10) + (key[10] == "a" ? "b" : "a") + key.substring(11);
    expect(RecoveryKeyGuard.containsRecoveryKey(broken), isFalse);
  });

  test("ignores ordinary messages and long base58-ish text", () {
    expect(RecoveryKeyGuard.containsRecoveryKey("see you saturday!"), isFalse);
    expect(
        RecoveryKeyGuard.containsRecoveryKey(
            "QmYwAPJzv5CZsnA625s3Xf2nemtYgPpHdWEz79ojWnPbdG ipfs hash"),
        isFalse);
    expect(RecoveryKeyGuard.containsRecoveryKey(""), isFalse);
  });
}
