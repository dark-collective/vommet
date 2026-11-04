import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:commet/client/matrix/auth/matrix_oidc_login_flow.dart';
import 'package:commet/client/matrix/database/matrix_database_io.dart';
import 'package:drift/isolate.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:matrix_dart_sdk_drift_db/matrix_dart_sdk_drift_db.dart';
import 'package:sqlite3/open.dart';

/// The app bundles sqlite (sqlite3_flutter_libs); a unit test on Linux uses
/// the system's, which often has only the versioned library name.
void useSystemSqlite() {
  if (!Platform.isLinux) return;
  open.overrideFor(OperatingSystem.linux, () {
    try {
      return DynamicLibrary.open("libsqlite3.so");
    } catch (_) {
      return DynamicLibrary.open("libsqlite3.so.0");
    }
  });
}

enum GuardRead { works, throws, hangs }

/// One account's database file as the app serves it on Android: a single
/// connection (`setupNativeDatabase`) behind a drift server, which every
/// client of the account connects to, the app's and the push handler's
/// alike (`MultiDatabaseServer`, found through `IsolateNameServer`).
class SharedAccountDatabase {
  final DriftIsolate _server;

  SharedAccountDatabase(File file)
      : _server = DriftIsolate.inCurrent(() => setupNativeDatabase(file),
            serialize: true);

  /// A client of the account as the app creates it: its own connection to
  /// the file, and the app's HTTP client around [server]'s.
  /// With [guardRead] `throws` or `hangs`, the HTTP client cannot read the
  /// stored session (a database that fails or is stuck).
  Future<matrix.Client> openClient(FakeContinuwuity server,
      {GuardRead guardRead = GuardRead.works}) async {
    final database = await connect();
    late final matrix.Client client;
    client = matrix.Client(
      FakeContinuwuity.clientName,
      database: database,
      httpClient: MatrixOidcLoginFlow.guardedHttpClient(
          server.httpClient,
          () => switch (guardRead) {
                GuardRead.works =>
                  database.getClient(FakeContinuwuity.clientName),
                GuardRead.throws =>
                  Future.error(StateError("database unavailable")),
                GuardRead.hangs => Completer<Map<String, dynamic>?>().future,
              },
          () => client),
    );
    // Only the refresh is under test: no sync loop in the background.
    client.backgroundSync = false;
    return client;
  }

  /// A client's own connection to the file.
  Future<matrix.DatabaseApi> connect() async => MatrixSdkDriftDatabase.init(
      await _server.connect(), FakeContinuwuity.clientName);

  Future<void> close() => _server.shutdownAll();
}

/// The homeserver side of an OIDC session on federated.nexus (Continuwuity
/// 26.9.1), modeled on its `refresh_session` (src/service/oauth/mod.rs):
/// access tokens last an hour, and each refresh replaces both tokens and
/// removes the old refresh token at once, so using it again is refused with
/// `invalid_grant`. There is no grace period.
class FakeContinuwuity {
  static const String clientName = "vommet_1099_account";
  static final Uri homeserver = Uri.parse("https://matrix.federated.nexus");
  static const String userId = "@penguinlord:federated.nexus";
  static const String deviceId = "OIDCDEVICE";
  static const String oidcClientId = "vommet-oidc-client";
  static const Duration accessTokenMaxAge = Duration(hours: 1);

  /// Holds the answer to the first accepted refresh until a later refresh
  /// was answered, so the two clients' requests overlap as they do when both
  /// refresh at the same moment.
  final bool holdFirstRefresh;

  FakeContinuwuity({this.holdFirstRefresh = false});

  int _generation = 0;
  String currentAccessToken = "access-0";
  String? currentRefreshToken = "refresh-0";

  int refreshRequests = 0;
  int refusedRefreshes = 0;
  int rejectedAccessTokens = 0;

  /// Answers this many next refreshes with a rate limit.
  int rateLimitRefreshes = 0;

  /// Answers this many next refreshes with a reverse proxy's error page.
  int proxyErrorRefreshes = 0;

  /// Answers the next refreshes with these, in order.
  final List<http.Response> scriptedRefreshes = [];

  /// Requests that reached a Matrix endpoint with the current token.
  int authorizedRequests = 0;
  final List<String> revokedTokens = [];

  bool _held = false;
  final Completer<void> _laterRefreshAnswered = Completer();

  late final http.Client httpClient = MockClient(_handle);

  /// Signs [client] in as the native OIDC sign-in leaves it.
  Future<void> signIn(matrix.Client client) => client.init(
        newHomeserver: homeserver,
        newToken: currentAccessToken,
        newTokenExpiresAt: DateTime.now().add(accessTokenMaxAge),
        newRefreshToken: currentRefreshToken,
        newUserID: userId,
        newDeviceID: deviceId,
        newOidcClientId: oidcClientId,
      );

  /// The server ends the session (signed out from another device).
  void revokeSession() {
    currentRefreshToken = null;
    currentAccessToken = "revoked";
  }

  Future<http.Response> _handle(http.Request request) async {
    final path = request.url.path;
    if (path == "/_matrix/client/v1/auth_metadata") {
      return _json(200, _authMetadata);
    }
    if (path == "/_continuwuity/oauth2/grant/token") {
      return _token(request.bodyFields);
    }
    if (path == "/_continuwuity/oauth2/client/revoke") {
      revokedTokens.add(request.bodyFields["token"] ?? "");
      return _json(200, {});
    }
    // A refresh removes the old access token (`set_token`), so any token but
    // the current one is unknown, not expired: no `soft_logout`
    // (src/api/router/auth.rs).
    if (request.headers["authorization"] != "Bearer $currentAccessToken") {
      rejectedAccessTokens++;
      return _json(401, {
        "errcode": "M_UNKNOWN_TOKEN",
        "error": "Unknown access token.",
      });
    }
    authorizedRequests++;
    if (path.endsWith("/filter")) return _json(200, {"filter_id": "1"});
    if (path == "/_matrix/client/v3/sync") {
      return _json(200, {"next_batch": "s$_generation"});
    }
    return _json(404, {"errcode": "M_UNRECOGNIZED", "error": "Unrecognized"});
  }

  Future<http.Response> _token(Map<String, String> body) async {
    if (body["grant_type"] != "refresh_token") {
      return _json(400, {"error": "unsupported_grant_type"});
    }
    refreshRequests++;
    if (scriptedRefreshes.isNotEmpty) return scriptedRefreshes.removeAt(0);
    if (proxyErrorRefreshes > 0) {
      proxyErrorRefreshes--;
      return http.Response("<html><body>400 Bad Request</body></html>", 400,
          headers: {"content-type": "text/html"});
    }
    if (rateLimitRefreshes > 0) {
      rateLimitRefreshes--;
      return _json(429, {
        "errcode": "M_LIMIT_EXCEEDED",
        "error": "Too many requests",
        "retry_after_ms": 100,
      });
    }
    if (body["client_id"] != oidcClientId ||
        currentRefreshToken == null ||
        body["refresh_token"] != currentRefreshToken) {
      refusedRefreshes++;
      if (!_laterRefreshAnswered.isCompleted) _laterRefreshAnswered.complete();
      return _json(400, {
        "error": "invalid_grant",
        "error_description": "Invalid refresh token"
      });
    }

    _generation++;
    currentAccessToken = "access-$_generation";
    currentRefreshToken = "refresh-$_generation";
    final response = _json(200, {
      "access_token": currentAccessToken,
      "token_type": "Bearer",
      "expires_in": accessTokenMaxAge.inSeconds,
      "refresh_token": currentRefreshToken,
      "scope": "urn:matrix:client:api:* urn:matrix:client:device:$deviceId",
    });

    if (holdFirstRefresh && !_held) {
      _held = true;
      await _laterRefreshAnswered.future;
    }
    return response;
  }

  static http.Response json(int status, Object body) => _json(status, body);

  static http.Response _json(int status, Object body) => http.Response(
        jsonEncode(body),
        status,
        headers: {"content-type": "application/json"},
      );

  // federated.nexus's /auth_metadata, as served on 2026-11-04.
  static final Map<String, Object?> _authMetadata = {
    "account_management_actions_supported": [
      "org.matrix.account_deactivate",
      "org.matrix.cross_signing_reset",
      "org.matrix.device_delete",
      "org.matrix.device_view",
      "org.matrix.devices_list",
      "org.matrix.profile",
    ],
    "account_management_uri":
        "https://matrix.federated.nexus/_continuwuity/account/deeplink",
    "authorization_endpoint":
        "https://matrix.federated.nexus/_continuwuity/oauth2/grant/authorization_code",
    "code_challenge_methods_supported": ["S256"],
    "device_authorization_endpoint":
        "https://matrix.federated.nexus/_continuwuity/oauth2/device",
    "grant_types_supported": [
      "authorization_code",
      "refresh_token",
      "urn:ietf:params:oauth:grant-type:device_code",
    ],
    "issuer": "https://matrix.federated.nexus/",
    "jwks_uri":
        "https://matrix.federated.nexus/_continuwuity/oauth2/client/keys.json",
    "prompt_values_supported": [],
    "registration_endpoint":
        "https://matrix.federated.nexus/_continuwuity/oauth2/client/register",
    "response_modes_supported": ["query", "fragment"],
    "response_types_supported": ["code"],
    "revocation_endpoint":
        "https://matrix.federated.nexus/_continuwuity/oauth2/client/revoke",
    "token_endpoint":
        "https://matrix.federated.nexus/_continuwuity/oauth2/grant/token",
  };
}
