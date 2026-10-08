import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:commet/client/auth.dart';
import 'package:commet/client/client.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/config/build_config.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/debug/log.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart' as matrix;

// Vommet: native OIDC sign-in (MSC2964/2965/2966/2967, the Matrix "next-gen
// auth" API), as Element X does it. The homeserver's login page opens in the
// browser and the app receives an authorization code back.
//
// The SDK's `oidcLogin`/`oidcRefresh` (matrix 6.1.1) read `expires_in` as
// milliseconds, but OAuth 2.0 gives seconds, so the SDK would think every
// token was about to expire and refresh it on every sync. We do the code
// exchange and the refresh here instead, with the right unit.
class MatrixOidcLoginFlow implements OidcLoginFlow {
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

  static bool get _useLoopback =>
      PlatformUtils.isLinux || PlatformUtils.isWindows;

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

    try {
      Uri registeredRedirect;
      Uri redirectUri;
      String callbackUrlScheme;

      if (_useLoopback) {
        var port = await _freeLoopbackPort();
        registeredRedirect = Uri.parse("http://127.0.0.1$loopbackPath");
        redirectUri = registeredRedirect.replace(port: port);
        callbackUrlScheme = "http://127.0.0.1:$port";
      } else {
        registeredRedirect = mobileRedirectUri;
        redirectUri = mobileRedirectUri;
        callbackUrlScheme = mobileScheme;
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
      );

      var result = await FlutterWebAuth2.authenticate(
          url: session.authenticationUri.toString(),
          callbackUrlScheme: callbackUrlScheme,
          options: const FlutterWebAuth2Options(
            useWebview: false,
          ));

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
    var stored = await mx.database.getClient(mx.clientName);
    var clientId = stored?.tryGet<String>('oidc_client_id');
    var refreshToken = stored?.tryGet<String>('refresh_token');

    if (clientId == null || refreshToken == null) {
      throw Exception("This session cannot be refreshed");
    }

    matrix.OidcAuthResponse? tokens;
    var delay = const Duration(seconds: 2);

    // The SDK logs out when this throws, so a network outage must not end
    // the session: keep retrying until the server answers, and only give up
    // when it refuses the refresh token.
    while (tokens == null) {
      try {
        tokens = await _requestTokens(mx, {
          'grant_type': 'refresh_token',
          'refresh_token': refreshToken,
          'client_id': clientId,
        });
      } on _TokenRequestRefused {
        rethrow;
      } catch (e) {
        Log.w("OIDC token refresh failed, retrying in $delay: $e");
        await Future.delayed(delay);
        if (delay < const Duration(minutes: 1)) delay *= 2;
      }
    }

    await mx.init(
      newHomeserver: mx.homeserver,
      newToken: tokens.accessToken,
      newTokenExpiresAt: expiresAt(tokens.expiresIn),
      newRefreshToken: tokens.refreshToken ?? refreshToken,
      newUserID: mx.userID,
      newDeviceID: mx.deviceID,
      newDeviceName: mx.deviceName,
      newOidcClientId: clientId,
    );
  }

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

    // 4xx: the server refused the grant (e.g. a revoked refresh token).
    // Anything else is worth retrying.
    if (response.statusCode >= 400 && response.statusCode < 500) {
      throw _TokenRequestRefused(response);
    }
    if (response.statusCode != 200) {
      throw Exception("Token endpoint returned ${response.statusCode}");
    }

    return matrix.OidcAuthResponse.fromJson(
        jsonDecode(utf8.decode(response.bodyBytes)));
  }

  static Future<int> _freeLoopbackPort() async {
    var socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    var port = socket.port;
    await socket.close();
    return port;
  }
}

class _TokenRequestRefused implements Exception {
  final int statusCode;
  final String body;

  _TokenRequestRefused(http.Response response)
      : statusCode = response.statusCode,
        body = utf8.decode(response.bodyBytes, allowMalformed: true);

  @override
  String toString() => "Token request refused ($statusCode): $body";
}
