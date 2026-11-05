// Vommet issue 1070: real SSSS crypto and two-device account data, without UI.
import 'dart:convert';

import 'package:commet/client/matrix/drafts/encrypted_draft_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart' as matrix;

import '../extensions/common_flows.dart';

void main() {
  testWidgets(
      'encrypted drafts: fresh device restore, conflict, send and clear',
      (tester) async {
    await tester.setupApp(); // Initializes the native crypto and database.
    final name = 'draft1070${DateTime.now().microsecondsSinceEpoch}';
    final password = 'test-$name';
    final registered = await http.post(
        Uri.https(tester.homeserver, '/_matrix/client/v3/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': name,
          'password': password,
          'auth': {'type': 'm.login.dummy'},
          'inhibit_login': true
        }));
    expect(registered.statusCode, 200); // Do not print credentials/body.
    Future<matrix.Client> device() async {
      final c = await tester.createTestClient(user: name, password: password);
      addTearDown(() => c.dispose(closeDatabase: true));
      await c.oneShotSync(timeout: Duration.zero);
      return c;
    }

    final first = await device();
    final key = await first.encryption!.ssss.createKey();
    await first.encryption!.ssss.setDefaultKeyId(key.keyId);
    await first.oneShotSync(timeout: Duration.zero);
    final room = await first.createRoom(initialState: [
      matrix.StateEvent(
          type: 'm.room.encryption',
          stateKey: '',
          content: {'algorithm': 'm.megolm.v1.aes-sha2'})
    ]);
    await first.oneShotSync(timeout: Duration.zero);
    final a = EncryptedDraftStore(first);
    addTearDown(a.dispose);
    await a.unlock(key);
    const text = 'héllo 世界 👩🏽‍💻';
    await a.write(await a.load(room), text, replyTo: r'$test-reply');
    final type = EncryptedDraftStore.typeFor(room, first.deviceID!);
    final wire = await first.getAccountData(first.userID!, type);
    expect(wire.keys, ['encrypted']);
    expect(jsonEncode(wire), isNot(contains(text)));

    // A brand-new device has no decrypted cache from the first store.
    final second = await device();
    final handle = second.encryption!.ssss.open(key.keyId);
    await handle.unlock(recoveryKey: key.recoveryKey, postUnlock: false);
    final b = EncryptedDraftStore(second);
    addTearDown(b.dispose);
    await b.unlock(handle);
    expect((await b.load(room)).drafts.single.text, text);
    expect((await b.load(room)).drafts.single.replyTo, r'$test-reply');
    final shownA = await a.load(room), shownB = await b.load(room);
    await a.write(shownA, 'phone');
    await b.write(shownB, 'desktop');
    await first.oneShotSync(timeout: Duration.zero);
    await second.oneShotSync(timeout: Duration.zero);
    final conflict = await a.load(room);
    expect(conflict.hasConflict, isTrue);
    expect(conflict.drafts.map((r) => r.text).toSet(), {'phone', 'desktop'});
    await a.write(conflict, text);
    final sentView = await a.load(room);
    final eventId = await first.getRoomById(room)!.sendTextEvent(text);
    expect(eventId, startsWith(r'$')); // Server-accepted send before clear.
    await a.write(sentView, '');
    await second.oneShotSync(timeout: Duration.zero);
    expect((await b.load(room)).drafts, isEmpty);
  });
}
