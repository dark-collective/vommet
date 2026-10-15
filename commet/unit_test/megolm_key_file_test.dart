import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:commet/client/matrix/key_export/megolm_key_file.dart';
import 'package:flutter_test/flutter_test.dart';

// Written by matrix-sdk-crypto-wasm (Element's crypto), passphrase below,
// 1000 rounds. Its session_key is structurally valid but not a real session.
const _elementFile = """
-----BEGIN MEGOLM SESSION DATA-----
AVuk1KnW5lBhJXvAKSI1/wZIkBbKvhheogfvcgfYTYdWAAAD6PPxFlGjkJKeGd41GteFFu+nSHKwSS7naa+gDVMcWpwTgHn2aX9RLarvm7bewFPQyKBo6NrG2s1lVhky9/rPz19+4ny+HunGtjzsMCbDSqwOf/UJ/JGzHxZaJh0ueZemlg+Pys+59GmJHQvX68Mo3ER0j3LGdwGuHU0ei770Sgq6qkZTI+51Ch7I/Aadhl88DJSu6ciBNvFuahj5cye4dttXUMwguPN6CO82PCLJtgBWqBSGa732bn1aalyYlIJy0rQGHB7w/2PIciNduHlM2rxnO9gbwTn+eEwWr9+rBE2iLfRzYaJuo3aJKc6XLlJb0LwT4G46XzsFQ9DMsDtYmPbR/g4H5JrNSOJkSrs1oWwDe80Tr+JoM/DeLo5gb98C1ZA4NMq+v+SEEqqgG9ZNNM+aWdR4le5NK9f3SC47zui0vxA7oCFeT2BGq9/lJxB0MplRLUc/NWnc5/VmABo6E8Nwujz43mBshNDwmNyCZU1ynm32PDjO7Qjj/fdPCr7Hf14OrPzM4iIC0JxUV78PYE/LZs4jKl2szsEeyzeYScjELmD8caU6FjL+Y1TWMdLWfN7yjYyumqPydXcnJyyYv7XWWMzr7DGpKsqu/VYmfV1YPXIQoKly9ovnS+7r4ViP3obQqTNfI68kal7wnot8r8eh95JgZgHG/snuIKWo6xCraUcpSvff4Tkv67F89M2Jz0pJhEvJLiTosgACgq0nIotVXJRzrrvvQAJNd1kfGw
-----END MEGOLM SESSION DATA-----
""";
const _passphrase = "correct horse ünïcode";

final _sessions = [
  {
    "algorithm": "m.megolm.v1.aes-sha2",
    "room_id": "!room:example.org",
    "session_id": "sid1",
    "sender_key": "abc",
    "sender_claimed_keys": {"ed25519": "def"},
    "forwarding_curve25519_key_chain": <String>[],
    "session_key": "ghi",
  }
];

Uint8List _payload() => utf8.encode(jsonEncode(_sessions));

void main() {
  test('reads a key file written by Element', () async {
    final sessions = await MegolmKeyFile.decryptSync(_elementFile, _passphrase);
    expect(sessions, hasLength(1));
    expect(sessions.first["room_id"], "!room:example.org");
    expect(sessions.first["session_id"], "sid1");
    expect(sessions.first["algorithm"], "m.megolm.v1.aes-sha2");

    // Optional: re-encrypt them for the Element interop script to read back.
    final out = Platform.environment["KEY_EXPORT_INTEROP_OUT"];
    if (out != null) {
      final file = await MegolmKeyFile.encryptSync(
          utf8.encode(jsonEncode(sessions)), _passphrase, 1000);
      File(out).writeAsStringSync(file);
    }
  });

  test('round trip', () async {
    final file = await MegolmKeyFile.encryptSync(_payload(), _passphrase, 1000);
    expect(file, startsWith(MegolmKeyFile.header));
    expect(file.trim(), endsWith(MegolmKeyFile.footer));
    expect(file.split("\n").every((l) => l.length <= 96), isTrue);
    final back = await MegolmKeyFile.decryptSync(file, _passphrase);
    expect(back, _sessions);
  });

  test('wrong passphrase', () async {
    final file = await MegolmKeyFile.encryptSync(_payload(), _passphrase, 10);
    expect(() => MegolmKeyFile.decryptSync(file, "nope"),
        throwsA(isA<WrongPassphraseException>()));
  });

  test('tampered file fails the MAC', () async {
    final file = await MegolmKeyFile.encryptSync(_payload(), _passphrase, 10);
    final lines = file.split("\n");
    final b = base64.decode(lines[1]);
    b[40] ^= 1;
    lines[1] = base64.encode(b);
    expect(() => MegolmKeyFile.decryptSync(lines.join("\n"), _passphrase),
        throwsA(isA<WrongPassphraseException>()));
  });

  test('a file asking for too many rounds is refused before deriving',
      () async {
    final file = await MegolmKeyFile.encryptSync(_payload(), _passphrase, 10);
    final lines = file.trim().split("\n");
    String withRounds(int rounds) {
      final data = base64.decode(lines.sublist(1, lines.length - 1).join());
      ByteData.sublistView(data, 33, 37).setUint32(0, rounds);
      return [lines.first, base64.encode(data), lines.last].join("\n");
    }

    // Refused at once (deriving 2^32-1 rounds would take hours), and not
    // reported as a wrong passphrase.
    for (final rounds in [0xffffffff, MegolmKeyFile.maxRounds + 1]) {
      await expectLater(
          MegolmKeyFile.decryptSync(withRounds(rounds), _passphrase),
          throwsA(predicate(
              (e) => e is KeyFileException && e is! WrongPassphraseException)));
    }
    expect(MegolmKeyFile.defaultRounds, lessThan(MegolmKeyFile.maxRounds));
  });

  test('not a key file', () {
    expect(() => MegolmKeyFile.decryptSync("hello", _passphrase),
        throwsA(isA<KeyFileException>()));
    expect(MegolmKeyFile.looksLikeKeyFile("hello"), isFalse);
  });

  test('IV bit 63 is cleared', () async {
    final iv = Uint8List(16)..fillRange(0, 16, 0xff);
    final file =
        await MegolmKeyFile.encryptSync(_payload(), _passphrase, 10, iv: iv);
    final lines = file.trim().split("\n");
    final data = base64.decode(lines.sublist(1, lines.length - 1).join());
    expect(data[17 + 8] & 0x80, 0);
    expect(await MegolmKeyFile.decryptSync(file, _passphrase), _sessions);
  });
}
