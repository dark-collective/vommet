// Vommet issue 1099, the other side: a refused refresh that no other client
// answered (the session was really ended on the server) still signs out, as
// Vommet issue 427 wants. The wait for another client's tokens is shortened.

import 'dart:io';

import 'package:commet/client/matrix/auth/matrix_oidc_login_flow.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;

import 'oidc_refresh_fake_server.dart';

void main() {
  late Directory dir;
  late SharedAccountDatabase database;
  matrix.Client? client;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp("vommet_1099_");
    database = SharedAccountDatabase(File("${dir.path}/data.db"));
    MatrixOidcLoginFlow.storedTokensWait = const Duration(milliseconds: 600);
  });

  tearDown(() async {
    MatrixOidcLoginFlow.storedTokensWait = const Duration(seconds: 30);
    await client?.dispose(closeDatabase: true);
    client = null;
    await database.close();
    await dir.delete(recursive: true);
  });

  test('a session ended on the server still signs out', () async {
    final server = FakeContinuwuity();
    final app = client = await database.openClient(server);
    await server.signIn(app);
    await MatrixOidcLoginFlow.attachRefresh(app);

    server.revokeSession();

    final clock = Stopwatch()..start();
    await expectLater(app.ensureNotSoftLoggedOut(const Duration(hours: 2)),
        throwsA(anything));
    clock.stop();

    expect(server.refusedRefreshes, 1);
    expect(app.isLogged(), isFalse);
    expect(await app.database.getClient(FakeContinuwuity.clientName), isNull);
    // It waited for another client's tokens, but not much longer.
    expect(
        clock.elapsed, greaterThanOrEqualTo(const Duration(milliseconds: 600)));
    expect(clock.elapsed, lessThan(const Duration(seconds: 10)));
  });

  test('a session ended on the server still signs out when a sync finds it',
      () async {
    final server = FakeContinuwuity();
    final app = client = await database.openClient(server);
    await server.signIn(app);
    await MatrixOidcLoginFlow.attachRefresh(app);

    server.revokeSession();
    await app.oneShotSync();

    expect(server.rejectedAccessTokens, 1);
    expect(server.refreshRequests, 0);
    expect(app.isLogged(), isFalse);
    expect(await app.database.getClient(FakeContinuwuity.clientName), isNull);
  });

  test('a rate-limited refresh is retried, not taken for a sign-out', () async {
    final server = FakeContinuwuity()..rateLimitRefreshes = 1;
    final app = client = await database.openClient(server);
    await server.signIn(app);
    await MatrixOidcLoginFlow.attachRefresh(app);

    await app.ensureNotSoftLoggedOut(const Duration(hours: 2));

    expect(server.refreshRequests, 2);
    expect(app.isLogged(), isTrue);
    expect(app.accessToken, server.currentAccessToken);
  });

  test('a proxy error page from the token endpoint is retried', () async {
    final server = FakeContinuwuity()..proxyErrorRefreshes = 1;
    final app = client = await database.openClient(server);
    await server.signIn(app);
    await MatrixOidcLoginFlow.attachRefresh(app);

    await app.ensureNotSoftLoggedOut(const Duration(hours: 2));

    expect(server.refreshRequests, 2);
    expect(app.isLogged(), isTrue);
    expect(app.accessToken, server.currentAccessToken);
  });

  test('a Matrix-style error from the token endpoint is retried', () async {
    final server = FakeContinuwuity();
    server.scriptedRefreshes.add(FakeContinuwuity.json(
        400, {"errcode": "M_UNRECOGNIZED", "error": "Unrecognized request"}));
    final app = client = await database.openClient(server);
    await server.signIn(app);
    await MatrixOidcLoginFlow.attachRefresh(app);

    await app.ensureNotSoftLoggedOut(const Duration(hours: 2));

    expect(server.refreshRequests, 2);
    expect(app.isLogged(), isTrue);
    expect(app.accessToken, server.currentAccessToken);
  });

  test('any OAuth error from the token endpoint is a refusal', () async {
    final server = FakeContinuwuity();
    server.scriptedRefreshes.add(FakeContinuwuity.json(400, {
      "error": "invalid_request",
      "error_description": "The session no longer exists"
    }));
    final app = client = await database.openClient(server);
    await server.signIn(app);
    await MatrixOidcLoginFlow.attachRefresh(app);

    await expectLater(app.ensureNotSoftLoggedOut(const Duration(hours: 2)),
        throwsA(anything));

    expect(server.refreshRequests, 1);
    expect(app.isLogged(), isFalse);
    expect(await app.database.getClient(FakeContinuwuity.clientName), isNull);
  });

  test('a refresh with nobody else refreshing takes the new tokens', () async {
    final server = FakeContinuwuity();
    final app = client = await database.openClient(server);
    await server.signIn(app);
    await MatrixOidcLoginFlow.attachRefresh(app);

    await app.ensureNotSoftLoggedOut(const Duration(hours: 2));

    expect(server.refusedRefreshes, 0);
    expect(app.isLogged(), isTrue);
    expect(app.accessToken, "access-1");
    final expires = app.accessTokenExpiresAt;
    expect(expires, isNotNull);
    expect(expires!.difference(DateTime.now()).inMinutes,
        inInclusiveRange(58, 60));
    final stored = await app.database.getClient(FakeContinuwuity.clientName);
    expect(stored?.tryGet<String>('refresh_token'), "refresh-1");
  });
}
