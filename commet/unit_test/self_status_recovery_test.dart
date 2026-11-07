import 'dart:async';
import 'dart:io';

import 'package:commet/client/matrix/matrix_server_features.dart';
import 'package:commet/main.dart' as app;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart' show MatrixException;
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/self_status_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await app.preferences.init();
  });
  for (final limited in [false, true]) {
    test('probe failure hands off without immediate self retry: $limited',
        () async {
      final f = SelfStatusFixture();
      await f.init();
      try {
        if (limited) {
          f.errorStatus = 429;
          f.errorCode = 'M_LIMIT_EXCEEDED';
          f.retryAfterMs = 180000;
        } else {
          f.presenceFailure = const SocketException('synthetic offline');
        }
        expect(profileStatus(await f.profile()), isNull);
        expect(f.presenceGets, 1,
            reason: 'failed probe is not immediately repeated');
      } finally {
        await f.close();
      }
    });
  }
  test('a first write honors the failed probe retry floor without a second GET',
      () async {
    final f = SelfStatusFixture()
      ..errorStatus = 429
      ..errorCode = 'M_LIMIT_EXCEEDED'
      ..retryAfterMs = 180000;
    await f.init();
    try {
      await expectLater(
          f.account.profile.setStatus(null), throwsA(isA<MatrixException>()));
      expect(f.presenceGets, 1);
      expect(f.requests.where((r) => r.method == 'PUT'), isEmpty);
    } finally {
      await f.close();
    }
  });
  for (final status in [403, 404, 429, 503]) {
    test('self GET recovery clock and session boundary: $status', () async {
      final f = SelfStatusFixture();
      await f.init();
      final c = SelfStatusClock(f.sdk);
      f.errorStatus = status;
      f.errorCode = status == 429 ? 'M_LIMIT_EXCEEDED' : 'M_UNKNOWN';
      f.retryAfterMs = 180000;
      try {
        expect((await c.read())?.statusMsg, isNull);
        expect(f.presenceGets, 1);
        c.elapse(const Duration(seconds: 59));
        await c.read();
        expect(f.presenceGets, 1);
        if (status == 429) {
          c.elapse(const Duration(seconds: 120));
          await c.read();
          expect(f.presenceGets, 1, reason: 'server retry floor');
          c.elapse(const Duration(seconds: 2));
        } else if (status == 503) {
          c.elapse(const Duration(seconds: 17));
          await c.read();
          expect(f.presenceGets, 2);
          c.elapse(const Duration(seconds: 76));
          await c.read();
          expect(f.presenceGets, 2, reason: 'second backoff is at least120s');
          c.elapse(const Duration(seconds: 76));
        } else {
          c.elapse(const Duration(days: 1));
          await c.read();
          expect(f.presenceGets, 1, reason: 'permanent4xx stops this session');
          f.sdk.bearerToken = '';
          await c.read();
          expect(f.presenceGets, 1,
              reason: 'empty token is not a valid replacement');
          f.sdk.bearerToken = 'synthetic-replacement';
        }
        f.errorStatus = null;
        expect((await c.read())?.statusMsg, 'SERVER B');
        final count = f.presenceGets;
        c.elapse(const Duration(seconds: 29));
        await c.read();
        expect(f.presenceGets, count);
        c.elapse(const Duration(seconds: 2));
        f.serverStatus = '';
        expect((await c.read())?.statusMsg, '');
      } finally {
        await c.close();
        await f.close();
      }
    });
  }
  test(
      '5s UI deadline keeps underlying GET single-flight and rejects late text',
      () async {
    final f = SelfStatusFixture();
    await f.init();
    final c = SelfStatusClock(f.sdk);
    f.delayedPresence = Completer<http.Response>();
    try {
      var settled = false;
      c.clock.run((_) => c.status.read().then((_) => settled = true));
      await c.flush();
      c.elapse(const Duration(seconds: 4));
      expect(settled, isFalse);
      c.elapse(const Duration(seconds: 1));
      expect(settled, isTrue);
      c.elapse(const Duration(minutes: 2));
      var reopened = false;
      c.clock.run((_) => c.status.read().then((_) => reopened = true));
      await c.flush();
      expect(f.presenceGets, 1,
          reason: 'old headers still pending after deadline/cooldown');
      expect(reopened, isTrue,
          reason: 'reopen returns the cached view immediately');
      c.clock.run((_) => f.delayedPresence!.complete(
          http.Response('{"presence":"online","status_msg":"LATE OLD"}', 200)));
      await c.flush();
      expect(c.status.cached, isNull);
      f.delayedPresence = null;
      expect((await c.read())?.statusMsg, 'SERVER B');
      // A late error still conveys a server retry floor, but not new text.
      c.elapse(const Duration(seconds: 31));
      f.delayedPresence = Completer<http.Response>();
      c.clock.run((_) => unawaited(c.status.read()));
      await c.flush();
      c.elapse(const Duration(seconds: 5));
      c.clock.run((_) => f.delayedPresence!.complete(http.Response(
          '{"errcode":"M_LIMIT_EXCEEDED","retry_after_ms":180000}', 429)));
      await c.flush();
      final requests = f.presenceGets;
      c.elapse(const Duration(seconds: 90));
      expect((await c.read())?.statusMsg, 'SERVER B');
      expect(f.presenceGets, requests,
          reason: 'late429 floor outlasts timeout cooldown');
    } finally {
      await c.close();
      await f.close();
    }
  });
  test('session replacement reprobes capabilities and isolates old clear/cache',
      () async {
    final f = SelfStatusFixture();
    await f.init();
    try {
      f.errorStatus = 403;
      expect((await MatrixServerFeatures.of(f.account)).presence, isFalse);
      f.errorStatus = null;
      f.sdk.bearerToken = 'synthetic-valid-replacement';
      expect(profileStatus(await f.profile()), 'SERVER B');
      await f.account.profile.setStatus(null);
      f.sdk.bearerToken = 'synthetic-next-session';
      f.serverStatus = 'NEW SESSION';
      expect(profileStatus(await f.profile()), 'NEW SESSION');
    } finally {
      await f.close();
    }
  });
  test(
      'control: failed older save permits queued clear; legacy clear and signed-out/closed guards',
      () async {
    final f = SelfStatusFixture();
    await f.init();
    try {
      await f.profile();
      final release = Completer<void>();
      f.delayedWrite = release;
      final save = f.account.profile.setStatus('OLD');
      final rejected = expectLater(save, throwsStateError);
      await f.delayedWriteStarted.future;
      final clear = f.account.profile.setStatus('');
      release.completeError(StateError('synthetic rejected save'));
      await rejected;
      await clear;
      expect(f.serverStatus, '');
      expect(profileStatus(await f.profile(refresh: false)), isNull);
      f.account.loggedIn = false;
      final count = f.requests.length;
      await f.account.profile.setStatus('SIGNED OUT');
      expect(f.requests, hasLength(count));
      f.account.loggedIn = true;
      await f.account.profile.onClientClosed();
      await f.account.profile.setStatus('CLOSED');
      expect(f.requests, hasLength(count));
    } finally {
      await f.close();
    }
    final legacy = SelfStatusFixture()
      ..errorStatus = 404
      ..errorCode = 'M_UNRECOGNIZED';
    await legacy.init();
    try {
      expect(profileStatus(await legacy.profile()), legacyStatus);
      await legacy.account.profile.setStatus(null);
      expect(profileStatus(await legacy.profile(refresh: false)), isNull);
    } finally {
      await legacy.close();
    }
  });
}
