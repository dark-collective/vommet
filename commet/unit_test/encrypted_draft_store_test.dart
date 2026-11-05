import 'dart:async';
import 'dart:convert';

import 'package:commet/client/matrix/drafts/draft_revision.dart';
import 'package:commet/client/matrix/drafts/encrypted_draft_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:matrix/msc_extensions/msc_4186_sliding_sync/translator.dart';

import 'helpers/draft_fixtures.dart';

void main() {
  const room = '!project:example.org';
  late DraftServer server;
  late DraftSdk phone, desktop;
  late EncryptedDraftStore a, b;
  late DraftTestCipher cipher;

  Matcher problem(DraftProblem p) =>
      isA<DraftStoreException>().having((e) => e.problem, 'problem', p);

  setUp(() async {
    server = DraftServer();
    phone = DraftSdk(server, 'phone');
    desktop = DraftSdk(server, 'desktop');
    cipher = DraftTestCipher();
    a = EncryptedDraftStore(phone, cipher: cipher);
    b = EncryptedDraftStore(desktop, cipher: cipher);
    await a.unlock(DraftHandle(phone, server.keyId));
    await b.unlock(DraftHandle(desktop, server.keyId));
  });
  tearDown(() async {
    await a.dispose();
    await b.dispose();
  });

  Future<void> bothSync() async {
    await phone.syncFromServer();
    await desktop.syncFromServer();
  }

  test(
    'Unicode text and reply survive restart; server has only ciphertext',
    () async {
      const text = 'héllo 世界 👩🏽‍💻\nquote " \\';
      await a.write(await a.load(room), text, replyTo: r'$reply');
      expect(cipher.sealed.single.codeUnits.every((c) => c < 128), isTrue);
      final wire = server.events.values.single;
      expect(wire.keys, ['encrypted']);
      expect(jsonEncode(wire), isNot(contains('reply')));
      await a.dispose();
      final restarted = DraftSdk(server, 'phone');
      await restarted.syncFromServer();
      a = EncryptedDraftStore(restarted, cipher: cipher);
      await expectLater(a.load(room), throwsA(problem(DraftProblem.locked)));
      await a.unlock(DraftHandle(restarted, server.keyId));
      final restored = (await a.load(room)).drafts.single;
      expect(restored.text, text);
      expect(restored.replyTo, r'$reply');
    },
  );

  test(
    'room and account isolation; thread schema cannot restore in main',
    () async {
      await a.write(await a.load(room), 'one');
      await bothSync();
      expect((await b.load('!other:example.org')).drafts, isEmpty);
      final other = DraftSdk(server, 'desktop', userID: '@other:example.org');
      await other.syncFromServer();
      final store = EncryptedDraftStore(other, cipher: cipher);
      addTearDown(store.dispose);
      await store.unlock(DraftHandle(other, server.keyId));
      expect((await store.load(room)).drafts, isEmpty);
      final type = EncryptedDraftStore.typeFor(room, 'phone');
      other.echo(type, server.events.values.single);
      await Future<void>.delayed(Duration.zero);
      await expectLater(
        store.load(room),
        throwsA(problem(DraftProblem.invalid)),
      );
      final raw = (await a.load(room)).drafts.single.toJson()
        ..['context'] = 'thread';
      expect(() => DraftRevision.fromJson(raw), throwsFormatException);
    },
  );

  test(
    'two offline writers retain both; explicit choice covers only shown versions',
    () async {
      final emptyA = await a.load(room), emptyB = await b.load(room);
      await Future.wait([
        a.write(emptyA, 'two', replyTo: r'$a'),
        b.write(emptyB, 'three', replyTo: r'$b'),
      ]);
      await bothSync();
      final shown = await a.load(room);
      expect(shown.hasConflict, isTrue);
      expect(shown.drafts.map((r) => r.text).toSet(), {'two', 'three'});
      await b.write(await b.load(room), 'four');
      // Phone hasn't shown desktop's new edit, so choosing the displayed phone
      // draft must not dismiss that unseen update.
      await a.write(shown, 'two', replyTo: r'$a');
      await bothSync();
      final later = await a.load(room);
      expect(later.drafts.map((r) => r.text).toSet(), {'two', 'four'});
      await a.write(later, 'chosen');
      await bothSync();
      expect((await b.load(room)).drafts.single.text, 'chosen');
    },
  );

  test(
    'clear suppresses known revisions but preserves unseen offline edits',
    () async {
      await a.write(await a.load(room), 'ready');
      await bothSync();
      final sent = await a.load(room), offline = await b.load(room);
      await a.write(
        sent,
        '',
      ); // Caller supplies this only after send acceptance.
      await b.write(offline, 'offline edit');
      await bothSync();
      final view = await a.load(room);
      expect(view.drafts.single.text, 'offline edit');
      expect(
        view.hasConflict,
        isTrue,
        reason: 'deletion and edit are concurrent',
      );
      await a.write(view, '');
      await bothSync();
      expect((await b.load(room)).drafts, isEmpty);
    },
  );

  test(
    'stale send completion cannot clear text typed after the send',
    () async {
      await a.write(await a.load(room), 'sending');
      final sent = await a.load(room);
      await a.write(sent, 'new typing');
      await expectLater(
        a.write(sent, ''),
        throwsA(problem(DraftProblem.stale)),
      );
      expect((await a.load(room)).drafts.single.text, 'new typing');
    },
  );

  test('reply-only persists; blank no-reply becomes a compact clear', () async {
    await a.write(await a.load(room), '', replyTo: r'$reply');
    expect((await a.load(room)).drafts.single.replyTo, r'$reply');
    await a.write(await a.load(room), ' \n ');
    final cleared = (await a.load(room)).records.single;
    expect(cleared.cleared, isTrue);
    expect(cleared.text, isEmpty);
    expect(cleared.replyTo, isNull);
  });

  test(
    'failed write preserves acknowledged text and queue can retry',
    () async {
      await a.write(await a.load(room), 'saved');
      server.rejectWrite = true;
      await expectLater(
        a.write(await a.load(room), 'unsaved'),
        throwsStateError,
      );
      expect((await a.load(room)).drafts.single.text, 'saved');
      server.rejectWrite = false;
      await a.write(await a.load(room), 'retry');
      expect((await a.load(room)).drafts.single.text, 'retry');
    },
  );

  test(
    'writes serialize; an outdated queued snapshot fails rather than overwrites',
    () async {
      final empty = await a.load(room);
      server.holdWrite = Completer<void>();
      final first = a.write(empty, 'first');
      final second = a.write(empty, 'second');
      final secondFailure = expectLater(
        second,
        throwsA(problem(DraftProblem.stale)),
      );
      await Future<void>.delayed(Duration.zero);
      expect(server.writes, 1);
      server.holdWrite!.complete();
      await first;
      await secondFailure;
      expect((await a.load(room)).drafts.single.text, 'first');
    },
  );

  test(
    'old sync echo cannot replace a newer acknowledged local revision',
    () async {
      await a.write(await a.load(room), 'old');
      final old = server.events.values.single;
      await a.write(await a.load(room), 'new');
      phone.echo(EncryptedDraftStore.typeFor(room, 'phone'), old);
      await Future<void>.delayed(Duration.zero);
      expect((await a.load(room)).drafts.single.text, 'new');
    },
  );

  test(
    'key reset pauses uploads; foreign and wrong keys never unlock data',
    () async {
      await a.write(await a.load(room), 'private');
      server.keyId = 'replacement';
      await expectLater(
        a.write(await a.load(room), 'bad'),
        throwsA(problem(DraftProblem.locked)),
      );
      expect(server.writes, 1);
      expect(a.isUnlocked, isFalse);
      await expectLater(
        a.unlock(DraftHandle(desktop, server.keyId)),
        throwsA(problem(DraftProblem.locked)),
      );
      await b.unlock(DraftHandle(desktop, server.keyId, 99));
      await desktop.syncFromServer();
      await expectLater(b.load(room), throwsA(problem(DraftProblem.invalid)));
    },
  );

  test(
    'corrupt ciphertext blocks restore and does not produce an empty view',
    () async {
      await a.write(await a.load(room), 'keep');
      final data = jsonDecode(jsonEncode(server.events.values.single))
          as Map<String, dynamic>;
      ((data['encrypted'] as Map)[server.keyId] as Map)['mac'] = 'bad';
      desktop.echo(EncryptedDraftStore.typeFor(room, 'phone'), data);
      await Future<void>.delayed(Duration.zero);
      await expectLater(b.load(room), throwsA(problem(DraftProblem.invalid)));
      expect(server.writes, 1);
    },
  );

  test(
    'oversized text and writer overflow fail without evicting data',
    () async {
      await expectLater(
        a.write(await a.load(room), 'é' * 8193),
        throwsFormatException,
      );
      expect(server.writes, 0);
      for (var i = 0; i < 17; i++) {
        desktop.echo(EncryptedDraftStore.typeFor(room, 'writer$i'), {});
      }
      await Future<void>.delayed(Duration.zero);
      await expectLater(b.load(room), throwsA(problem(DraftProblem.limit)));
    },
  );

  test(
    'unrelated/repeated sync does no decrypt or redundant room notification',
    () async {
      final rooms = <String>[];
      final subscription = b.changedRooms.listen(rooms.add);
      addTearDown(subscription.cancel);
      await a.write(await a.load(room), 'hello');
      await desktop.syncFromServer();
      await desktop.syncFromServer();
      desktop.echo('unrelated', {'value': 1});
      await Future<void>.delayed(Duration.zero);
      expect(rooms, [room]);
      expect(cipher.opens, 0);
      await b.load(room);
      expect(cipher.opens, 1);
    },
  );

  test(
    'logout locks keys; dispose cancels queued work before an upload',
    () async {
      phone.onLoginStateChanged.add(matrix.LoginState.softLoggedOut);
      await Future<void>.delayed(Duration.zero);
      await expectLater(a.load(room), throwsA(problem(DraftProblem.locked)));
      await a.unlock(DraftHandle(phone, server.keyId));
      cipher.holdSeal = Completer<void>();
      final writing = a.write(await a.load(room), 'must not upload');
      final rejected = expectLater(
        writing,
        throwsA(problem(DraftProblem.closed)),
      );
      await Future<void>.delayed(Duration.zero);
      await a.dispose();
      cipher.holdSeal!.complete();
      await rejected;
      expect(server.writes, 0);
    },
  );
  test('sliding sync global account-data extension reaches the same store',
      () async {
    await a.write(await a.load(room), 'from sliding sync');
    final update = slidingSyncResponseToSyncUpdate({
      'pos': 'draft-test',
      'extensions': {
        'account_data': {
          'global': [
            {
              'type': EncryptedDraftStore.typeFor(room, 'phone'),
              'content': server.events.values.single,
            }
          ]
        }
      }
    }, userId: desktop.userID)
        .syncUpdate;
    desktop.onSync.add(update);
    await Future<void>.delayed(Duration.zero);
    expect((await b.load(room)).drafts.single.text, 'from sliding sync');
  });

  test('unchanged text/reply does not upload another revision', () async {
    await a.write(await a.load(room), 'same', replyTo: r'$reply');
    await a.write(await a.load(room), 'same', replyTo: r'$reply');
    expect(server.writes, 1);
    expect((await a.load(room)).drafts.single.revision, 1);
  });

  test('key reset during encryption cancels the old-key upload', () async {
    cipher.holdSeal = Completer<void>();
    final writing = a.write(await a.load(room), 'private');
    final rejected =
        expectLater(writing, throwsA(problem(DraftProblem.locked)));
    await Future<void>.delayed(Duration.zero);
    server.keyId = 'new-key';
    cipher.holdSeal!.complete();
    await rejected;
    expect(server.writes, 0);
  });
  test('one store owns a device client until dispose', () async {
    expect(() => EncryptedDraftStore(phone, cipher: cipher),
        throwsA(problem(DraftProblem.stale)));
    await a.dispose();
    a = EncryptedDraftStore(phone, cipher: cipher);
    await a.unlock(DraftHandle(phone, server.keyId));
    expect((await a.load(room)).drafts, isEmpty);
  });

  test('oversized and plaintext account-data envelopes remain invalid',
      () async {
    final type = EncryptedDraftStore.typeFor(room, 'phone');
    for (final data in [
      {'text': 'must never be treated as a readable draft'},
      {
        'encrypted': {
          server.keyId: {'iv': 'x' * 100000, 'mac': 'x', 'ciphertext': 'x'}
        }
      },
    ]) {
      desktop.echo(type, data);
      await Future<void>.delayed(Duration.zero);
      await expectLater(b.load(room), throwsA(problem(DraftProblem.invalid)));
    }
    expect(cipher.opens, 0);
  });
}
