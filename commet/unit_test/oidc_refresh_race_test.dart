// Vommet issue 1099: a federated.nexus (Continuwuity) account signed itself
// out on Android. The app and the push handler each run a client for the
// account on the same database; Continuwuity hands out 1 h access tokens and
// rotates the refresh token on every use, so when both clients refreshed at
// once, the second was refused and its sign-out cleared the shared database.
//
// Two real SDK clients, each with its own connection to the account's one
// database (as the app and the push handler connect to the database isolate),
// refresh through the real soft-logout path against a token endpoint that
// behaves like Continuwuity's.

import 'dart:convert';
import 'dart:io';

import 'package:commet/client/matrix/auth/matrix_oidc_login_flow.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart' as matrix;

import 'oidc_refresh_fake_server.dart';

void main() {
  late Directory dir;
  late SharedAccountDatabase database;
  final open = <matrix.Client>[];

  setUp(() async {
    dir = await Directory.systemTemp.createTemp("vommet_1099_");
    database = SharedAccountDatabase(File("${dir.path}/data.db"));
  });

  final readStoredSession = MatrixOidcLoginFlow.readStoredSession;
  final writeTokens = MatrixOidcLoginFlow.writeTokens;

  tearDown(() async {
    MatrixOidcLoginFlow.readStoredSession = readStoredSession;
    MatrixOidcLoginFlow.writeTokens = writeTokens;
    for (final client in open) {
      await client.dispose(closeDatabase: true);
    }
    open.clear();
    await database.close();
    await dir.delete(recursive: true);
  });

  Future<matrix.Client> openClient(FakeContinuwuity server) async {
    final client = await database.openClient(server);
    open.add(client);
    return client;
  }

  /// The app signed in with OIDC, as the reporter's federated.nexus account,
  /// and the push handler loading the same account from the same database.
  Future<(matrix.Client, matrix.Client)> appAndPush(
      FakeContinuwuity server) async {
    final app = await openClient(server);
    await server.signIn(app);
    await MatrixOidcLoginFlow.attachRefresh(app);

    final push = await openClient(server);
    await MatrixOidcLoginFlow.attachRefresh(push);
    await push.init();
    expect(push.isLogged(), isTrue);
    return (app, push);
  }

  Future<void> expectSessionKept(
      FakeContinuwuity server, List<matrix.Client> clients) async {
    expect(server.revokedTokens, isEmpty,
        reason: "nothing may sign the session out on the server");
    for (final client in clients) {
      expect(client.isLogged(), isTrue);
      expect(client.accessToken, server.currentAccessToken);
    }
    // The database they share still holds the session, with the tokens the
    // server will accept next time.
    final stored =
        await clients.first.database.getClient(FakeContinuwuity.clientName);
    expect(stored?.tryGet<String>('refresh_token'), server.currentRefreshToken);
    expect(stored?.tryGet<String>('token'), server.currentAccessToken);
  }

  test(
      'the app and the push handler refresh at once: both stay signed in '
      'with the rotated tokens', () async {
    final server = FakeContinuwuity(holdFirstRefresh: true);
    final (app, push) = await appAndPush(server);

    // The 1 h token runs out while a push is handled: both clients refresh
    // through the SDK's soft-logout path, with the one stored refresh token.
    final results = await Future.wait([
      _refresh(app),
      _refresh(push),
    ]);

    expect(server.refreshRequests, 2);
    expect(server.refusedRefreshes, 1,
        reason: "one client must have reused the rotated refresh token");
    expect(results, everyElement(isNull),
        reason: "neither refresh may fail: ${results.whereType<Object>()}");
    await expectSessionKept(server, [app, push]);
  });

  test(
      'the push handler refreshes a moment after the app: it takes the '
      'tokens the app stored, and the app stays signed in', () async {
    final server = FakeContinuwuity();
    final (app, push) = await appAndPush(server);

    expect(await _refresh(app), isNull);
    expect(await _refresh(push), isNull);

    // Refreshing again would have ended the app's new access token.
    expect(server.refreshRequests, 1);
    await app.oneShotSync();
    await push.oneShotSync();
    expect(server.rejectedAccessTokens, 0);
    await expectSessionKept(server, [app, push]);
  });

  test(
      'the push handler syncs with the token the app replaced: it takes the '
      'tokens the app stored instead of clearing the database', () async {
    final server = FakeContinuwuity();
    final (app, push) = await appAndPush(server);

    expect(await _refresh(app), isNull);

    // Continuwuity answers the replaced token as signed out, not expired.
    await push.oneShotSync();
    expect(server.rejectedAccessTokens, 1);
    expect(server.refreshRequests, 1,
        reason: "the push handler must not rotate the tokens again");
    await push.oneShotSync();
    await app.oneShotSync();
    expect(server.rejectedAccessTokens, 1);
    await expectSessionKept(server, [app, push]);
  });

  test(
      'a request with a token the client itself replaced is sent again with '
      'the current one, without rotating the tokens again', () async {
    final server = FakeContinuwuity();
    final (app, push) = await appAndPush(server);

    expect(await _refresh(app), isNull);
    // A request the app built just before its refresh, sent after it.
    final before = server.authorizedRequests;
    final response = await app.httpClient
        .get(_syncUrl, headers: {"authorization": "Bearer access-0"});
    expect(response.statusCode, 200);
    expect(server.authorizedRequests, before + 1);

    await app.oneShotSync();
    await push.oneShotSync();
    expect(server.refreshRequests, 1);
    await expectSessionKept(server, [app, push]);
  });

  test(
      'a streamed request with a replaced token is answered as retry-later, '
      'not as signed out', () async {
    final server = FakeContinuwuity();
    final (app, _) = await appAndPush(server);

    expect(await _refresh(app), isNull);
    final upload = http.StreamedRequest("POST", _syncUrl)
      ..headers["authorization"] = "Bearer access-0";
    upload.sink
      ..add(utf8.encode("{}"))
      ..close();
    final response =
        await http.Response.fromStream(await app.httpClient.send(upload));
    expect(response.statusCode, 429);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    expect(body["errcode"], "M_LIMIT_EXCEEDED");
    expect(body["soft_logout"], isNull);
    expect(app.isLogged(), isTrue);
  });

  test(
      'a request with a replaced token while the database still holds it '
      '(the client is storing its refresh) is sent again too', () async {
    final server = FakeContinuwuity();
    final (app, _) = await appAndPush(server);

    expect(await _refresh(app), isNull);
    // The app holds the new token, the database the old one, as in the
    // moment before the refresh's write lands.
    await app.database.updateClient(
        FakeContinuwuity.homeserver.toString(),
        "access-0",
        DateTime.now().add(const Duration(hours: 1)),
        "refresh-0",
        FakeContinuwuity.userId,
        FakeContinuwuity.deviceId,
        null,
        null,
        null,
        FakeContinuwuity.oidcClientId);

    final response = await app.httpClient
        .get(_syncUrl, headers: {"authorization": "Bearer access-0"});
    expect(response.statusCode, 200);
  });

  Future<(matrix.Client, matrix.Client)> appAndPushWithGuardRead(
      FakeContinuwuity server, GuardRead guardRead) async {
    final app = await openClient(server);
    await server.signIn(app);
    await MatrixOidcLoginFlow.attachRefresh(app);
    final push = await database.openClient(server, guardRead: guardRead);
    open.add(push);
    await MatrixOidcLoginFlow.attachRefresh(push);
    await push.init();
    return (app, push);
  }

  test(
      'a sync with the token another client replaced keeps the session when '
      'the database fails meanwhile', () async {
    final server = FakeContinuwuity();
    final (app, push) = await appAndPushWithGuardRead(server, GuardRead.throws);

    expect(await _refresh(app), isNull);
    // The refresh's own reads fail too, for a moment.
    var failures = 2;
    MatrixOidcLoginFlow.readStoredSession = (mx) {
      if (identical(mx, push) && failures-- > 0) {
        return Future.error(StateError("database is locked"));
      }
      return readStoredSession(mx);
    };
    await push.oneShotSync();

    expect(failures, lessThan(0));
    expect(server.refreshRequests, 1);
    await push.oneShotSync();
    await expectSessionKept(server, [app, push]);
  });

  test(
      'a sync with the token another client replaced keeps the session when '
      'the database is stuck at that moment', () async {
    final server = FakeContinuwuity();
    final (app, push) = await appAndPushWithGuardRead(server, GuardRead.hangs);

    expect(await _refresh(app), isNull);
    await push.oneShotSync();

    expect(server.refreshRequests, 1);
    await expectSessionKept(server, [app, push]);
  });

  test('a refresh whose tokens fail to store at first keeps them', () async {
    final server = FakeContinuwuity();
    final (app, push) = await appAndPush(server);

    var failures = 1;
    MatrixOidcLoginFlow.writeTokens = (mx, tokens, clientId) {
      if (failures-- > 0) return Future.error(StateError("disk I/O error"));
      return writeTokens(mx, tokens, clientId);
    };
    expect(await _refresh(app), isNull);

    expect(failures, lessThan(0));
    expect(server.refreshRequests, 1);
    await app.oneShotSync();
    await push.oneShotSync();
    await expectSessionKept(server, [app, push]);
  });

  test(
      'a request with an old token the client did not replace itself is not '
      'sent with the current one', () async {
    final server = FakeContinuwuity();
    final (app, _) = await appAndPush(server);

    expect(await _refresh(app), isNull);
    final before = server.authorizedRequests;
    // E.g. built for a session signed out since.
    final response = await app.httpClient.get(_syncUrl,
        headers: {"authorization": "Bearer from-an-earlier-session"});
    expect(response.statusCode, 429);
    expect(server.authorizedRequests, before);
    expect(app.isLogged(), isTrue);
  });
}

final _syncUrl = FakeContinuwuity.homeserver.resolve("/_matrix/client/v3/sync");

/// Refreshes through the SDK's soft-logout path (as its sync loop does when
/// the token is about to expire); returns the error, if any.
Future<Object?> _refresh(matrix.Client client) async {
  try {
    await client.ensureNotSoftLoggedOut(const Duration(hours: 2));
    return null;
  } catch (e) {
    return e;
  }
}
