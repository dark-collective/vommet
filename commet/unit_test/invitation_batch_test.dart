import 'dart:async';
import 'package:commet/ui/organisms/invitation_view/batch_invite_source.dart';
import 'package:commet/utils/invitations/invitation_batch.dart';
import 'package:flutter_test/flutter_test.dart';

BatchInviteItem item(
  String user,
  String room, {
  String? parent,
  InviteOperation operation = InviteOperation.invite,
}) =>
    BatchInviteItem(
      userId: user,
      roomId: room,
      roomName: room,
      parentRoomId: parent,
      operation: operation,
    );
InvitationBatchTask task(
  List<BatchInviteItem> items, {
  Future<InviteCheck> Function(BatchInviteItem)? check,
  required Future<void> Function(BatchInviteItem) send,
  Duration? Function(Object)? retryAfter,
  Future<void> Function(Duration)? sleep,
  String account = 'test',
}) =>
    InvitationBatchTask(
      accountId: account,
      name: 'Space',
      items: items,
      check: check ?? (_) async => InviteCheck.send,
      send: send,
      reasonFor: (_) => 'failure',
      uncertain: (e) => e is TimeoutException,
      retryAfter: retryAfter,
      sleep: sleep,
    );
void main() {
  test(
    'deduplicates by full ID, destination and operation, preserving case',
    () async {
      final sent = <Object>[];
      final t = task([
        item('@A:x', '!r'),
        item('@A:x', '!r'),
        item('@a:x', '!r'),
        item('@A:x', '!r', operation: InviteOperation.history),
      ], send: (i) async => sent.add(i.key));
      await t.start();
      expect(sent.length, 3);
      expect(t.count(InviteOutcome.sent), 3);
      t.dispose();
    },
  );
  test(
    'retries only failed pairs, never another room for the same person',
    () async {
      final calls = <String>[];
      bool fail = true;
      final t = task(
        [
          item('alex', 'space'),
          item('jordan', 'space'),
          item('jordan', 'voice', parent: 'space'),
        ],
        send: (i) async {
          calls.add('${i.userId}/${i.roomId}');
          if (i.roomId == 'voice' && fail) throw StateError('no');
        },
      );
      await t.start();
      expect(t.count(InviteOutcome.sent), 2);
      expect(t.count(InviteOutcome.failed), 1);
      fail = false;
      await t.retry();
      expect(calls, [
        'alex/space',
        'jordan/space',
        'jordan/voice',
        'jordan/voice',
      ]);
      expect(t.needsAttention, false);
      t.dispose();
    },
  );
  test(
    'failed parent holds only that person subtree; retry resumes in order',
    () async {
      final calls = <String>[];
      bool fail = true;
      final t = task(
        [
          item('a', 'space'),
          item('a', 'child', parent: 'space'),
          item('b', 'space'),
          item('b', 'child', parent: 'space'),
        ],
        send: (i) async {
          calls.add('${i.userId}/${i.roomId}');
          if (i.userId == 'a' && i.roomId == 'space' && fail)
            throw StateError('no');
        },
      );
      await t.start();
      expect(calls, ['a/space', 'b/space', 'b/child']);
      expect(t.items[1].outcome, InviteOutcome.held);
      fail = false;
      await t.retry();
      expect(calls, ['a/space', 'b/space', 'b/child', 'a/space', 'a/child']);
      t.dispose();
    },
  );
  test('fresh membership skips joined and pending invitations', () async {
    var sends = 0;
    final t = task(
      [item('a', 'space'), item('b', 'space')],
      check: (i) async =>
          i.userId == 'a' ? InviteCheck.joined : InviteCheck.invited,
      send: (_) async {
        sends++;
      },
    );
    await t.start();
    expect(sends, 0);
    expect(t.count(InviteOutcome.skipped), 2);
    t.dispose();
  });
  test(
    'permission loss is blocked; children are checked on their own',
    () async {
      var sends = 0;
      final t = task(
        [item('a', 'space'), item('a', 'room', parent: 'space')],
        check: (_) async => InviteCheck.blocked,
        send: (_) async {
          sends++;
        },
      );
      await t.start();
      expect(sends, 0);
      expect(t.count(InviteOutcome.blocked), 2);
      expect(t.count(InviteOutcome.held), 0);
      t.dispose();
    },
  );
  test(
    'stop during in-flight request preserves acceptance and unsent work',
    () async {
      final gate = Completer<void>();
      final began = Completer<void>();
      final calls = <String>[];
      final t = task(
        [item('a', '1'), item('a', '2'), item('a', '3')],
        send: (i) async {
          calls.add(i.roomId);
          if (i.roomId == '1') {
            began.complete();
            await gate.future;
          }
        },
      );
      final run = t.start();
      await began.future;
      t.stop();
      gate.complete();
      await run;
      expect(calls, ['1']);
      expect(t.count(InviteOutcome.sent), 1);
      expect(t.count(InviteOutcome.canceled), 2);
      await t.resume();
      expect(calls, ['1', '2', '3']);
      t.dispose();
    },
  );
  test('stop during preflight does not dispatch the checked item', () async {
    final gate = Completer<InviteCheck>();
    var sends = 0;
    final t = task(
      [item('a', 'r')],
      check: (_) => gate.future,
      send: (_) async {
        sends++;
      },
    );
    final run = t.start();
    t.stop();
    gate.complete(InviteCheck.send);
    await run;
    expect(sends, 0);
    expect(t.items.single.outcome, InviteOutcome.canceled);
    t.dispose();
  });
  test(
    'uncertain dispatch is not part of ordinary retries, can reconcile',
    () async {
      var membership = InviteCheck.send;
      var sends = 0;
      final t = task(
        [item('a', 'r')],
        check: (_) async => membership,
        send: (_) async {
          sends++;
          throw TimeoutException('unknown');
        },
      );
      await t.start();
      expect(t.items.single.outcome, InviteOutcome.unconfirmed);
      await t.retry();
      expect(sends, 1);
      await t.reconcile();
      expect(t.items.single.outcome, InviteOutcome.unconfirmed);
      membership = InviteCheck.invited;
      await t.reconcile();
      expect(t.items.single.outcome, InviteOutcome.skipped);
      expect(t.count(InviteOutcome.sent), 0);
      expect(sends, 1);
      t.dispose();
    },
  );
  test(
    'uncertain preflight failed before dispatch is safe to retry normally',
    () async {
      var sends = 0;
      final t = task(
        [item('a', 'r')],
        check: (_) async => throw TimeoutException('check'),
        send: (_) async {
          sends++;
        },
      );
      await t.start();
      expect(t.items.single.outcome, InviteOutcome.failed);
      expect(sends, 0);
      t.dispose();
    },
  );
  test('rate limits wait then check membership before retrying', () async {
    var sends = 0;
    var checks = 0;
    final delays = <Duration>[];
    final t = task(
      [item('a', 'r')],
      check: (_) async {
        checks++;
        return checks == 1 ? InviteCheck.send : InviteCheck.invited;
      },
      send: (_) async {
        sends++;
        throw StateError('rate');
      },
      retryAfter: (_) => const Duration(seconds: 2),
      sleep: (d) async => delays.add(d),
    );
    await t.start();
    expect(sends, 1);
    expect(checks, 2);
    expect(delays, [const Duration(seconds: 2)]);
    expect(t.items.single.outcome, InviteOutcome.skipped);
    t.dispose();
  });
  test(
    'parallel batches reserve pairs per account until the request settles',
    () async {
      final gate = Completer<void>();
      var sends = 0;
      final a = task(
        [item('a', 'r')],
        send: (_) async {
          sends++;
          await gate.future;
        },
      );
      final b = task(
        [item('a', 'r'), item('a', 'child', parent: 'r')],
        send: (_) async {
          sends++;
        },
      );
      final run = a.start();
      await b.start();
      expect(sends, 1);
      expect(b.count(InviteOutcome.held), 2);
      gate.complete();
      await run;
      expect(a.count(InviteOutcome.sent), 1);
      a.dispose();
      b.dispose();
    },
  );
  test('history failures never resend accepted invitations', () async {
    var calls = <InviteOperation>[];
    bool fail = true;
    final t = task(
      [item('a', 'r'), item('a', 'r', operation: InviteOperation.history)],
      send: (i) async {
        calls.add(i.operation);
        if (i.operation == InviteOperation.history && fail)
          throw StateError('history');
      },
    );
    await t.start();
    fail = false;
    await t.retry();
    expect(calls, [
      InviteOperation.invite,
      InviteOperation.history,
      InviteOperation.history,
    ]);
    t.dispose();
  });
  test(
    'repeat start and overlapping retry calls cannot dispatch twice',
    () async {
      var calls = 0;
      final gate = Completer<void>();
      final t = task(
        [item('a', 'r')],
        send: (_) async {
          calls++;
          await gate.future;
        },
      );
      final run = t.start();
      await t.start();
      await t.retry();
      await t.resume();
      expect(calls, 1);
      gate.complete();
      await run;
      t.dispose();
    },
  );
  test('stop interrupts a server backoff without another dispatch', () async {
    final sleeping = Completer<void>();
    final never = Completer<void>();
    var sends = 0;
    final t = task([item('a', 'r')],
        send: (_) async {
          sends++;
          throw StateError('rate');
        },
        retryAfter: (_) => const Duration(minutes: 5),
        sleep: (_) {
          sleeping.complete();
          return never.future;
        });
    final run = t.start();
    await sleeping.future;
    t.stop();
    await run;
    expect(sends, 1);
    expect(t.items.single.outcome, InviteOutcome.canceled);
    t.dispose();
  });
  test(
      'confirmed membership after an unknown parent allows only unsent children',
      () async {
    final calls = <String>[];
    var rootMembership = InviteCheck.send;
    final t = task([item('a', 'space'), item('a', 'room', parent: 'space')],
        check: (i) async =>
            i.roomId == 'space' ? rootMembership : InviteCheck.send,
        send: (i) async {
          calls.add(i.roomId);
          if (i.roomId == 'space') throw TimeoutException('unknown');
        });
    await t.start();
    expect(t.items.last.outcome, InviteOutcome.held);
    rootMembership = InviteCheck.joined;
    await t.reconcile();
    expect(t.items.first.outcome, InviteOutcome.skipped);
    expect(t.items.last.outcome, InviteOutcome.held);
    await t.resume();
    expect(calls, ['space', 'room']);
    expect(t.items.last.outcome, InviteOutcome.sent);
    t.dispose();
  });
  test('a space that cannot be invited to does not hold its rooms', () async {
    final calls = <String>[];
    final space = item('a', 'space')..outcome = InviteOutcome.blocked;
    final t = task(
      [space, item('a', 'room', parent: 'space'), item('b', 'space')],
      check: (i) async =>
          i.roomId == 'space' ? InviteCheck.blocked : InviteCheck.send,
      send: (i) async => calls.add('${i.userId}/${i.roomId}'),
    );
    await t.start();
    expect(calls, ['a/room']);
    expect(t.items[1].outcome, InviteOutcome.sent);
    expect(t.items[2].outcome, InviteOutcome.blocked);
    expect(t.count(InviteOutcome.held), 0);
    t.dispose();
  });
  test('start reserves only requests still waiting', () async {
    final gate = Completer<void>();
    final a = task([item('a', 'r')], send: (_) => gate.future);
    final joined = item('a', 'r')
      ..outcome = InviteOutcome.skipped
      ..reason = 'Already joined';
    final b = task([joined], send: (_) async {});
    final run = a.start();
    await b.start();
    expect(joined.outcome, InviteOutcome.skipped);
    expect(joined.reason, 'Already joined');
    expect(b.needsAttention, isFalse);
    gate.complete();
    await run;
    a.dispose();
    b.dispose();
  });
  test('stop during a rate-limited send ends as not sent, not failed',
      () async {
    var sends = 0;
    late final InvitationBatchTask t;
    t = task(
      [item('a', 'r')],
      send: (_) async {
        sends++;
        t.stop();
        throw StateError('rate');
      },
      retryAfter: (_) => const Duration(seconds: 2),
      sleep: (_) async {},
    );
    await t.start();
    expect(sends, 1);
    expect(t.items.single.outcome, InviteOutcome.canceled);
    expect(t.canResume, isTrue);
    expect(t.canRetry, isFalse);
    t.dispose();
  });
  test('one failed membership check does not stop the others', () async {
    final checked = <(String, String)>[];
    final failed = await BatchInviteSource.checkEach(
      ['a', 'b'],
      ['r1', 'r2'],
      (user, room) async {
        if (user == 'a' && room == 'r1') throw StateError('server error');
        checked.add((user, room));
      },
    );
    expect(failed, {('a', 'r1')});
    expect(checked, [('a', 'r2'), ('b', 'r1'), ('b', 'r2')]);
  });
}
