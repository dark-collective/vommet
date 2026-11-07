// Vommet issue 1170: exercise real Client.init and OIDC renewal against the
// consumed Drift store, with failures at the DatabaseApi boundary. All data
// is synthetic; assertions never render session values or key material.
import 'dart:async';

import 'package:commet/client/matrix/auth/matrix_oidc_login_flow.dart';
import 'package:drift/native.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:matrix/src/utils/client_init_exception.dart';
import 'package:matrix_dart_sdk_drift_db/matrix_dart_sdk_drift_db.dart';

import 'oidc_refresh_fake_server.dart';

void main() {
  late MatrixSdkDriftDatabase store;
  late _FailingSessionDatabase database;
  late matrix.Client client;
  late FakeContinuwuity server;
  final errors = <Object>[];
  final retryDelays = <Duration>[];

  setUp(() async {
    store = await MatrixSdkDriftDatabase.init(
        NativeDatabase.memory(), FakeContinuwuity.clientName);
    await store.insertClient(
        FakeContinuwuity.clientName,
        FakeContinuwuity.homeserver.toString(),
        'access-0',
        DateTime.now().add(const Duration(hours: 1)),
        'refresh-0',
        FakeContinuwuity.userId,
        FakeContinuwuity.deviceId,
        null,
        null,
        null,
        FakeContinuwuity.oidcClientId);
    // A disposable synthetic encryption key record in the real store.
    await store.storeOlmSession('identity', 'session', 'synthetic-pickle', 0);
    database = _FailingSessionDatabase(store);
    server = FakeContinuwuity();
    client = matrix.Client(FakeContinuwuity.clientName,
        database: database, httpClient: server.httpClient);
    client.backgroundSync = false;
    client.onLoginStateChanged.stream.listen((_) {}, onError: (Object e) {
      errors.add(e);
    });
    client.onLoginStateChanged.add(matrix.LoginState.softLoggedOut);
    await server.signIn(client);
    errors.clear();
    retryDelays.clear();
  });

  tearDown(() async {
    await client.dispose();
  });

  // SQLite and mocked HTTP can yield to the real event queue. Pump those
  // events while advancing retry time only on the fake clock.
  Future<Object?> renew() async {
    final clock = FakeAsync();
    Object? error;
    var finished = false;
    final initialFailures = database.failures;
    final initialWaits = retryDelays.length;
    clock.run((_) {
      unawaited(
          client.ensureNotSoftLoggedOut(const Duration(hours: 2)).then<void>(
        (_) {
          finished = true;
        },
        onError: (Object failure, StackTrace _) {
          error = failure;
          finished = true;
        },
      ));
    });
    for (var pump = 0; pump < 1000 && !finished; pump++) {
      clock.elapse(Duration.zero);
      if (finished) break;
      final waits = retryDelays.length - initialWaits;
      if (database.failures > initialFailures + waits &&
          clock.pendingTimers.isNotEmpty) {
        expect(waits, lessThan(5), reason: 'at most five retry waits');
        final delay = clock.pendingTimers.single.duration;
        retryDelays.add(delay);
        final failures = database.failures;
        const tick = Duration(microseconds: 1);
        clock.elapse(delay - tick);
        expect(database.failures, failures,
            reason: 'initialization must wait until the retry deadline');
        clock.elapse(tick);
      }
      await Future<void>.delayed(Duration.zero);
    }
    expect(finished, isTrue, reason: 'renewal must settle');
    expect(clock.pendingTimers, isEmpty);
    return error;
  }

  Future<void> expectKept() async {
    expect([
      (await store.getClient(FakeContinuwuity.clientName)) != null,
      (await store.getAllOlmSessions()).isNotEmpty,
    ], [
      true,
      true
    ], reason: 'the account row and stored keys must survive');
  }

  for (final point in ['getClient', 'updateClient']) {
    test('a one-shot $point renewal error keeps account and keys for retry',
        () async {
      client.onLoginStateChanged.add(matrix.LoginState.softLoggedOut);
      database.fail(point);
      final states = <matrix.InitState>[];
      await expectLater(client.init(onInitStateChanged: states.add),
          throwsA(isA<ClientInitException>()));
      await expectKept();
      expect(client.onLoginStateChanged.value, matrix.LoginState.softLoggedOut);
      expect(states.last, matrix.InitState.error);
      expect(errors.length, 1);
      await client.init();
      expect(client.onLoginStateChanged.value, matrix.LoginState.loggedIn);
      await expectKept();
    });

    test(
        'OIDC renewal retries one-shot $point init failure without rotating again',
        () async {
      // Read stored session, write tokens, then fail only the init DB call.
      database.fail(point, skip: 1);
      client.onSoftLogout = MatrixOidcLoginFlow.refreshSession;
      final error = await renew();
      await expectKept();
      expect(error == null, isTrue);
      expect(client.onLoginStateChanged.value, matrix.LoginState.loggedIn);
      expect(server.refreshRequests, 1);
      expect(server.revokedTokens.isEmpty, isTrue);
      expect(errors.length, 1);
    });
  }

  test('exhausted renewal init attempts surface error and permit later renewal',
      () async {
    database.fail('updateClient', skip: 1, count: 6);
    client.onSoftLogout = MatrixOidcLoginFlow.refreshSession;
    final error = await renew();
    await expectKept();
    expect(error is ClientInitException, isTrue);
    expect(database.failures, 6, reason: 'initial attempt plus five retries');
    expect(errors.length, 6);
    expect(retryDelays.length, 5);
    for (var retry = 0; retry < retryDelays.length; retry++) {
      final ceiling = Duration(seconds: 1 << retry);
      expect(retryDelays[retry], greaterThanOrEqualTo(ceiling ~/ 2));
      expect(retryDelays[retry], lessThan(ceiling));
    }
    expect(server.refreshRequests, 1);
    expect(server.revokedTokens.isEmpty, isTrue);
    expect(client.onLoginStateChanged.value, matrix.LoginState.softLoggedOut);
    // A failed shared renewal future must be released; a later call runs.
    expect(await renew() == null, isTrue);
    expect(client.onLoginStateChanged.value, matrix.LoginState.loggedIn);
    expect(server.refreshRequests, 2,
        reason: 'one rotation per explicitly requested renewal');
    await expectKept();
  });

  // Compatibility controls: these deliberately pass on the unchanged base.
  test('non-renewal initialization failure still destroys invalid account',
      () async {
    client.onLoginStateChanged.add(matrix.LoginState.loggedOut);
    database.fail('getClient');
    await expectLater(client.init(), throwsA(isA<ClientInitException>()));
    expect(
        (await store.getClient(FakeContinuwuity.clientName)) == null, isTrue);
    expect((await store.getAllOlmSessions()).isEmpty, isTrue);
  });

  test('storage refusal still preserves a non-renewal account', () async {
    client.onLoginStateChanged.add(matrix.LoginState.loggedOut);
    database.fail('getClient',
        error: 'IndexedDB transaction aborted: synthetic');
    await expectLater(client.init(), throwsA(isA<ClientInitException>()));
    await expectKept();
  });

  test('explicit logout still removes account and keys', () async {
    await client.logout();
    expect(
        (await store.getClient(FakeContinuwuity.clientName)) == null, isTrue);
    expect((await store.getAllOlmSessions()).isEmpty, isTrue);
  });
}

/// Only session operations fail; all exercised persistence is delegated to
/// the real store. Unexpected calls throw rather than silently becoming fakes.
class _FailingSessionDatabase implements matrix.DatabaseApi {
  final matrix.DatabaseApi delegate;
  _FailingSessionDatabase(this.delegate);
  String? _point;
  int _skip = 0;
  int _remaining = 0;
  String _error = 'synthetic database unavailable';
  int failures = 0;

  void fail(String point, {int skip = 0, int count = 1, String? error}) {
    _point = point;
    _skip = skip;
    _remaining = count;
    if (error != null) _error = error;
  }

  void _check(String point) {
    if (_point != point || _remaining == 0) return;
    if (_skip > 0) {
      _skip--;
      return;
    }
    _remaining--;
    failures++;
    throw _error;
  }

  @override
  Future<Map<String, dynamic>?> getClient(String name) async {
    _check('getClient');
    return delegate.getClient(name);
  }

  @override
  Future<dynamic> updateClient(
      String homeserverUrl,
      String token,
      DateTime? tokenExpiresAt,
      String? refreshToken,
      String userId,
      String? deviceId,
      String? deviceName,
      String? prevBatch,
      String? olmAccount,
      String? oidcClientId) async {
    _check('updateClient');
    return delegate.updateClient(
        homeserverUrl,
        token,
        tokenExpiresAt,
        refreshToken,
        userId,
        deviceId,
        deviceName,
        prevBatch,
        olmAccount,
        oidcClientId);
  }

  @override
  Future<void> cacheCustomObject(String key, Map<String, Object?> object) =>
      delegate.cacheCustomObject(key, object);
  @override
  Future<({Map<String, Object?> content, DateTime savedAt})?>
      getCustomCacheObject(String key) => delegate.getCustomCacheObject(key);
  @override
  Future<void> clear() => delegate.clear();
  @override
  Future<void> delete() => delegate.delete();
  @override
  Future<dynamic> close() => delegate.close();
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
      'Unexpected database operation ${invocation.memberName}');
}
