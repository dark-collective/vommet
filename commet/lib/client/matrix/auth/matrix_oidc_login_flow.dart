import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:commet/client/auth.dart';
import 'package:commet/client/client.dart';
import 'package:commet/client/matrix/auth/loopback_redirect_server.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/config/build_config.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/debug/log.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart' as matrix;
import 'package:matrix/src/utils/client_init_exception.dart';

// Vommet: native OIDC sign-in (MSC2964/2965/2966/2967, the Matrix "next-gen
// auth" API), as Element X does it. The homeserver's login page opens in the
// browser and the app receives an authorization code back.
//
// The SDK's `oidcLogin`/`oidcRefresh` (matrix 6.1.1) read `expires_in` as
// milliseconds, but OAuth 2.0 gives seconds, so the SDK would think every
// token was about to expire and refresh it on every sync. We do the code
// exchange and the refresh here instead, with the right unit.
class MatrixOidcLoginFlow implements OidcLoginFlow {
  // Vommet (Vommet issue 254): open the server's sign-up page instead of its
  // login page (`prompt=create`); the new account is signed in afterwards.
  final bool createAccount;

  MatrixOidcLoginFlow({this.createAccount = false});

  static final Uri clientUri = Uri.parse("https://vommet.app");

  // Desktop: RFC 8252 loopback redirect. It is registered without a port and
  // used with one; servers match loopback IP literals on any port (Tuwunel
  // only does so for IP literals, not "localhost").
  static const String loopbackPath = "/oauth/callback";

  // Mobile: a private-use scheme, which must be client_uri's host in
  // reverse-DNS order (vommet.app -> app.vommet) and carry no authority.
  static const String mobileScheme = "app.vommet";
  static final Uri mobileRedirectUri = Uri.parse("$mobileScheme:/oauth");

  static bool get isSupportedPlatform => !PlatformUtils.isWeb;

  /// Whether the homeserver's OAuth 2.0 metadata offers what this flow needs.
  static bool isUsable(matrix.GetAuthMetadataResponse metadata) {
    return metadata.responseTypesSupported.contains("code") &&
        metadata.grantTypesSupported.contains("authorization_code") &&
        metadata.grantTypesSupported.contains("refresh_token") &&
        metadata.codeChallengeMethodsSupported.contains("S256");
  }

  @override
  Future<LoginResult> submit(Client client) async {
    if (client is! MatrixClient) {
      return LoginResultError(
          "Attemted to login with the wrong type of client");
    }

    var mx = client.getMatrixClient();
    LoopbackRedirectServer? loopbackServer;

    try {
      Uri registeredRedirect;
      Uri redirectUri;

      if (LoopbackRedirectServer.replacesWebAuth) {
        loopbackServer = await LoopbackRedirectServer.bind(loopbackPath);
        registeredRedirect = Uri.parse("http://127.0.0.1$loopbackPath");
        redirectUri = registeredRedirect.replace(port: loopbackServer.port);
      } else {
        registeredRedirect = mobileRedirectUri;
        redirectUri = mobileRedirectUri;
      }

      var oidcClient = await mx.registerOidcClient(
        redirectUris: [registeredRedirect],
        applicationType: matrix.OidcApplicationType.native,
        clientInformation: matrix.OidcClientInformation(
          clientName: BuildConfig.appName,
          clientUri: clientUri,
          logoUri: null,
          tosUri: null,
          policyUri: null,
        ),
      );

      var session = await mx.initOidcLoginSession(
        oidcClientData: oidcClient,
        redirectUri: redirectUri,
        prompt: createAccount ? "create" : null,
      );

      String result;
      if (loopbackServer != null) {
        var redirect =
            await loopbackServer.authenticate(session.authenticationUri);
        if (redirect == null) return LoginResultCancelled();
        result = redirect.toString();
      } else {
        result = await FlutterWebAuth2.authenticate(
            url: session.authenticationUri.toString(),
            callbackUrlScheme: mobileScheme,
            options: const FlutterWebAuth2Options(
              useWebview: false,
            ));
      }

      var params = Uri.parse(result).queryParameters;
      var error = params["error"];
      if (error != null) {
        if (error == "access_denied") return LoginResultCancelled();
        return LoginResultError(params["error_description"] ?? error);
      }

      var code = params["code"];
      var state = params["state"];
      if (code == null || state == null) {
        return LoginResultFailed();
      }

      if (state != session.state) {
        return LoginResultError(
            "The sign-in response did not match this sign-in attempt");
      }

      var tokens = await _requestTokens(mx, {
        'grant_type': 'authorization_code',
        'code': code,
        'redirect_uri': session.redirectUri.toString(),
        'client_id': session.oidcClientData.clientId,
        'code_verifier': session.codeVerifier,
      });

      mx.onSoftLogout = refreshSession;
      await mx.init(
        newHomeserver: mx.homeserver,
        newToken: tokens.accessToken,
        newRefreshToken: tokens.refreshToken,
        newTokenExpiresAt: expiresAt(tokens.expiresIn),
        newOidcClientId: session.oidcClientData.clientId,
      );

      return mx.isLogged() ? LoginResultSuccess() : LoginResultFailed();
    } catch (e, t) {
      Log.onError(e, t);
      // I didn't spell this wrong, its just like that in flutter_web_auth_2
      if (e is PlatformException && e.code == "CANCELED") {
        return LoginResultCancelled();
      }
      return LoginResultError(e.toString());
    } finally {
      await loopbackServer?.close();
    }
  }

  /// Installs [refreshSession] on a stored session that signed in with OIDC.
  /// Other sessions keep no handler, so a soft logout still logs them out as
  /// before (and their logins still ask for no refresh token).
  static Future<void> attachRefresh(matrix.Client mx) async {
    var stored = await mx.database.getClient(mx.clientName);
    if (stored?.tryGet<String>('oidc_client_id') != null) {
      mx.onSoftLogout = refreshSession;
    }
  }

  /// `Client.onSoftLogout` handler: gets a new access token with the stored
  /// refresh token. Throwing makes the SDK log out.
  static Future<void> refreshSession(matrix.Client mx) async {
    // Throwing here signs out and clears the database, so a database that
    // fails for a moment is asked again.
    var stored = await _retryDatabase(
        "read the stored session", () => readStoredSession(mx));
    var clientId = stored?.tryGet<String>('oidc_client_id');
    var refreshToken = stored?.tryGet<String>('refresh_token');

    if (clientId == null || refreshToken == null) {
      throw Exception("This session cannot be refreshed");
    }

    // Vommet issue 1099: on Android the app and the push handler each run a
    // client for the account, on the same database. Servers that rotate the
    // refresh token (Continuwuity, MAS) end the old access token with it, so
    // when one client refreshes, the other's token stops working. If another
    // client already stored new tokens, take them: refreshing again would end
    // the token that client is using, and the server answers a token it
    // replaced as signed out, not as expired, which clears the database both
    // clients share.
    var tokens = _storedNewerTokens(mx, stored!,
        notExpiringBefore: DateTime.now().add(const Duration(minutes: 1)));
    if (tokens != null) {
      Log.i("Another client of this account already refreshed the OIDC "
          "session, using the tokens it stored");
    }

    var delay = const Duration(seconds: 2);

    // The SDK logs out when this throws, so a network outage must not end
    // the session: keep retrying until the server answers, and only give up
    // when it refuses the refresh token.
    while (tokens == null) {
      try {
        var response = await _requestTokens(mx, {
          'grant_type': 'refresh_token',
          'refresh_token': refreshToken,
          'client_id': clientId,
        });
        tokens = _RefreshedTokens(
          accessToken: response.accessToken,
          refreshToken: response.refreshToken ?? refreshToken,
          expiresAt: expiresAt(response.expiresIn),
        );
      } on _TokenRequestRefused catch (refused) {
        // The refresh token can also have been used by another client a
        // moment ago, both refreshing at once: that client is about to store
        // the new tokens. Take those instead of signing out.
        tokens = await _tokensStoredByAnotherClient(mx, refreshToken);
        if (tokens == null) {
          Log.w("OIDC token refresh refused: $refused");
          rethrow;
        }
        Log.i("OIDC refresh token was already used by another client of "
            "this account, using the tokens it stored");
      } catch (e) {
        // A malformed answer can echo tokens: name only the kind of error.
        var reason = e is FormatException || e is TypeError
            ? "malformed response (${e.runtimeType})"
            : "$e";
        Log.w("OIDC token refresh failed, retrying in $delay: $reason");
        await Future.delayed(delay);
        if (delay < const Duration(minutes: 1)) delay *= 2;
      }
    }

    final replaced = mx.accessToken;
    if (replaced != null && replaced != tokens.accessToken) {
      final own = _replacedTokens[mx] ??= <String>[];
      own.add(replaced);
      if (own.length > 4) own.removeAt(0);
    }

    // Vommet issue 1170: keep 1099's token write before init, then retry only
    // renewal initialization failures. Do not request/rotate tokens again.
    final refreshed = tokens;
    await _retryDatabase(
        "store the new tokens", () => writeTokens(mx, refreshed, clientId));
    final random = Random();
    var initDelayMs = 1000;
    for (var attempt = 1;; attempt++) {
      try {
        await mx.init(
          newHomeserver: mx.homeserver,
          newToken: tokens.accessToken,
          newTokenExpiresAt: tokens.expiresAt,
          newRefreshToken: tokens.refreshToken,
          newUserID: mx.userID,
          newDeviceID: mx.deviceID,
          newDeviceName: mx.deviceName,
          newOidcClientId: clientId,
        );
        return;
      } on ClientInitException {
        if (attempt >= 6) rethrow;
        // Equal jitter keeps each wait below its exponential ceiling.
        final halfDelayMs = initDelayMs ~/ 2;
        final initDelay =
            Duration(milliseconds: halfDelayMs + random.nextInt(halfDelayMs));
        // Never log the exception's session fields or database payload.
        Log.w("Session renewal initialization failed, retrying in $initDelay");
        await Future.delayed(initDelay);
        initDelayMs *= 2;
      }
    }
  }

  /// Reads an account's stored session. Tests replace it.
  static Future<Map<String, dynamic>?> Function(matrix.Client mx)
      readStoredSession = (mx) => mx.database.getClient(mx.clientName);

  /// Stores refreshed tokens for an account, as `init` does in a soft
  /// logout. Tests replace it.
  static Future<void> Function(
          matrix.Client mx, _RefreshedTokens tokens, String clientId)
      writeTokens = (mx, tokens, clientId) async {
    final userId = mx.userID;
    final homeserver = mx.homeserver;
    if (userId == null || homeserver == null) return;
    await mx.database.updateClient(
      homeserver.toString(),
      tokens.accessToken,
      tokens.expiresAt,
      tokens.refreshToken,
      userId,
      mx.deviceID,
      mx.deviceName,
      mx.prevBatch,
      mx.encryption?.pickledOlmAccount,
      clientId,
    );
  };

  /// Access tokens each client replaced by refreshing, the latest few.
  static final Expando<List<String>> _replacedTokens = Expando();

  static Future<T> _retryDatabase<T>(
      String what, Future<T> Function() operation) async {
    var delay = const Duration(seconds: 1);
    for (var attempt = 1;; attempt++) {
      try {
        return await operation();
      } catch (e) {
        if (attempt >= 6) rethrow;
        Log.w("Could not $what, trying again in $delay: $e");
        await Future.delayed(delay);
        delay *= 2;
      }
    }
  }

  /// How long a refused refresh waits for another client of the account to
  /// store the tokens it got for the same refresh token. That client stores
  /// them as soon as the server answers it, but on a phone it may be a
  /// throttled background isolate on a slow network. Tests shorten it.
  static Duration storedTokensWait = const Duration(seconds: 30);

  static const Duration _storedTokensPoll = Duration(milliseconds: 250);

  /// The tokens another client of this account stored after refreshing with
  /// [usedRefreshToken], or null when none appear within [storedTokensWait]
  /// (the server really refused the session).
  static Future<_RefreshedTokens?> _tokensStoredByAnotherClient(
      matrix.Client mx, String usedRefreshToken) async {
    final deadline = DateTime.now().add(storedTokensWait);
    while (true) {
      try {
        final stored = await readStoredSession(mx);
        // Signed out meanwhile: nothing to take over.
        if (stored == null || stored.tryGet<String>('token') == null) {
          return null;
        }
        if (stored.tryGet<String>('refresh_token') != usedRefreshToken) {
          return _storedNewerTokens(mx, stored);
        }
      } catch (e) {
        // A database hiccup is no reason to sign out: look again.
        Log.w("Could not read the stored session: $e");
      }
      if (!DateTime.now().isBefore(deadline)) return null;
      await Future.delayed(_storedTokensPoll);
    }
  }

  /// The tokens in [stored] when another client of this session stored them
  /// (they differ from the ones [mx] uses), or null. With
  /// [notExpiringBefore], tokens that expire earlier are not taken: the
  /// stored refresh token renews them instead.
  static _RefreshedTokens? _storedNewerTokens(
      matrix.Client mx, Map<String, dynamic> stored,
      {DateTime? notExpiringBefore}) {
    final accessToken = stored.tryGet<String>('token');
    final refreshToken = stored.tryGet<String>('refresh_token');
    if (accessToken == null || refreshToken == null) return null;
    if (accessToken == mx.accessToken) return null;
    // Only this session's own tokens.
    if (stored.tryGet<String>('user_id') != mx.userID ||
        stored.tryGet<String>('device_id') != mx.deviceID) {
      return null;
    }
    final expiresAtMs =
        int.tryParse(stored.tryGet<String>('token_expires_at') ?? '');
    final expires = expiresAtMs == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(expiresAtMs);
    if (notExpiringBefore != null &&
        expires != null &&
        expires.isBefore(notExpiringBefore)) {
      return null;
    }
    return _RefreshedTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAt: expires,
    );
  }

  /// The HTTP client for an account's [matrix.Client]. When another client
  /// of an OIDC session refreshed it, a request with the token it replaced is
  /// answered `M_UNKNOWN_TOKEN` without `soft_logout`, on which the SDK's
  /// sync clears the database. That answer is marked a soft logout here, so
  /// the SDK calls [refreshSession], which takes the stored tokens. A token
  /// the database still holds keeps its answer: that session really ended.
  /// A request sent with a token the client itself replaced by refreshing is
  /// sent again with the current one. [readStored] reads the account's stored
  /// session, [client] is the account's client.
  static http.Client guardedHttpClient(
          http.Client inner,
          Future<Map<String, dynamic>?> Function() readStored,
          matrix.Client Function() client) =>
      _ReplacedTokenGuard(inner, () {
        final mx = client();
        return (mx.accessToken, _replacedTokens[mx] ?? const <String>[]);
      }, () async {
        final stored = await readStored();
        if (stored?.tryGet<String>('oidc_client_id') == null) return null;
        return stored?.tryGet<String>('token');
      });

  /// `expires_in` is in seconds (RFC 6749 §5.1).
  static DateTime? expiresAt(int? expiresIn) {
    if (expiresIn == null) return null;
    return DateTime.now().add(Duration(seconds: expiresIn));
  }

  static Future<matrix.OidcAuthResponse> _requestTokens(
      matrix.Client mx, Map<String, String> body) async {
    var metadata = await mx.getAuthMetadata();
    var response = await mx.httpClient.post(
      metadata.tokenEndpoint,
      body: body,
      headers: {'content-type': 'application/x-www-form-urlencoded'},
    );

    // The server refused the grant (e.g. a revoked refresh token). Anything
    // else, rate limits and error pages included, is worth retrying.
    if (_TokenRequestRefused.isRefusal(response)) {
      throw _TokenRequestRefused(response);
    }
    if (response.statusCode != 200) {
      throw Exception("Token endpoint returned ${response.statusCode}");
    }

    return matrix.OidcAuthResponse.fromJson(
        jsonDecode(utf8.decode(response.bodyBytes)));
  }
}

class _RefreshedTokens {
  final String accessToken;
  final String refreshToken;
  final DateTime? expiresAt;

  _RefreshedTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
  });
}

class _TokenRequestRefused implements Exception {
  final int statusCode;
  final String body;

  _TokenRequestRefused(http.Response response)
      : statusCode = response.statusCode,
        body = _short(utf8.decode(response.bodyBytes, allowMalformed: true));

  // RFC 6749 §5.2: a refused grant is a 400 (401 for the client) with an
  // OAuth `error`. A 429, a proxy's error page and the like are not.
  static bool isRefusal(http.Response response) {
    if (response.statusCode != 400 && response.statusCode != 401) {
      return false;
    }
    try {
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      // Matrix errors carry an `errcode`, OAuth errors never do.
      return body is Map &&
          body["error"] is String &&
          !body.containsKey("errcode");
    } catch (_) {
      return false;
    }
  }

  static String _short(String s) =>
      s.length > 300 ? "${s.substring(0, 300)}…" : s;

  @override
  String toString() => "Token request refused ($statusCode): $body";
}

/// See [MatrixOidcLoginFlow.guardedHttpClient].
class _ReplacedTokenGuard extends http.BaseClient {
  final http.Client _inner;

  /// The access token the client uses now, and the ones it replaced.
  final (String?, List<String>) Function() _tokens;

  /// The access token the database holds for an OIDC session, or null.
  final Future<String?> Function() _storedOidcToken;

  _ReplacedTokenGuard(this._inner, this._tokens, this._storedOidcToken);

  // The SDK's timeout covers reading the body only once send returns.
  static const _bodyTimeout = Duration(seconds: 30);
  static const _databaseTimeout = Duration(seconds: 5);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _send(request, mayResend: true);

  Future<http.StreamedResponse> _send(http.BaseRequest request,
      {required bool mayResend}) async {
    final response = await _inner.send(request);
    if (response.statusCode != 401) return response;

    final used = request.headers["authorization"];
    final bytes = await response.stream.toBytes().timeout(_bodyTimeout);
    http.StreamedResponse answer(List<int> body, [int? status]) =>
        http.StreamedResponse(
          Stream.value(body),
          status ?? response.statusCode,
          contentLength: body.length,
          request: response.request,
          headers: response.headers,
          isRedirect: response.isRedirect,
          persistentConnection: response.persistentConnection,
          reasonPhrase: response.reasonPhrase,
        );

    if (used == null || !used.startsWith("Bearer ")) return answer(bytes);
    Map<String, dynamic> body;
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<String, dynamic>) return answer(bytes);
      body = decoded;
    } catch (_) {
      return answer(bytes);
    }
    if (body["errcode"] != "M_UNKNOWN_TOKEN" || body["soft_logout"] == true) {
      return answer(bytes);
    }

    String? current;
    var replaced = const <String>[];
    try {
      (current, replaced) = _tokens();
    } catch (_) {}
    if (current == null) return answer(bytes);

    if ("Bearer $current" != used) {
      final retryLater = answer(
          utf8.encode(jsonEncode({
            "errcode": "M_LIMIT_EXCEEDED",
            "error": "Access token was replaced, retry",
            "retry_after_ms": 1000,
          })),
          429);
      // A token from before a sign-in again, or one replaced again while
      // this was resent: never send it with the current session's token.
      if (!mayResend || !replaced.contains(used.substring(7))) {
        return retryLater;
      }
      // The client replaced this token itself after building the request:
      // not a sign-out. The server refused it before running it, so send it
      // again with the current token; refreshing again would end that one.
      Log.i("A request used an access token this client has replaced, "
          "sending it again");
      if (request is http.Request) {
        final again = http.Request(request.method, request.url)
          ..headers.addAll(request.headers)
          ..followRedirects = request.followRedirects
          ..maxRedirects = request.maxRedirects
          ..persistentConnection = request.persistentConnection
          ..bodyBytes = request.bodyBytes;
        again.headers["authorization"] = "Bearer $current";
        return _send(again, mayResend: false);
      }
      // A streamed body cannot be sent twice: ask the caller to retry.
      return retryLater;
    }

    // The token is the client's current one. The database holding another
    // means another client of the session refreshed it: a soft logout, on
    // which [MatrixOidcLoginFlow.refreshSession] takes the stored tokens. If
    // the database cannot tell, also a soft logout: the refresh decides, and
    // a session that really ended is still refused there.
    String? stored;
    try {
      stored = await _storedOidcToken().timeout(_databaseTimeout);
      if (stored == null || stored == current) return answer(bytes);
    } catch (e) {
      Log.w("Could not read the stored session for a rejected token: $e");
    }
    Log.i("Access token was replaced by another client of this account, "
        "treating its rejection as a soft logout");
    return answer(utf8.encode(jsonEncode({...body, "soft_logout": true})));
  }

  @override
  void close() => _inner.close();
}
