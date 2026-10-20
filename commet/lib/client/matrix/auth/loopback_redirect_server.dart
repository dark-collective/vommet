import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

// Vommet: opens a sign-in page in the user's default browser and receives
// the redirect back on a 127.0.0.1 port (RFC 8252 loopback redirect).
//
// On macOS flutter_web_auth_2 always uses ASWebAuthenticationSession, which
// opens Safari unless the default browser supports that API (Firefox doesn't),
// so the sign-in page ignored the default browser (Vommet issue 510).
class LoopbackRedirectServer {
  static const Duration defaultTimeout = Duration(minutes: 10);

  /// Whether sign-in uses this instead of flutter_web_auth_2 (macOS only;
  /// on Linux and Windows the plugin already opens the default browser).
  static bool get replacesWebAuth => !kIsWeb && Platform.isMacOS;

  final HttpServer _server;
  final String path;

  LoopbackRedirectServer._(this._server, this.path);

  int get port => _server.port;

  /// The redirect URI to give the server, e.g. http://127.0.0.1:<port>/login
  Uri get redirectUri =>
      Uri(scheme: "http", host: "127.0.0.1", port: port, path: path);

  /// Listens on a free loopback port for a request to [path].
  static Future<LoopbackRedirectServer> bind(String path) async {
    var server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return LoopbackRedirectServer._(server, path);
  }

  /// Opens [url] in the default browser and waits for the redirect. Returns
  /// the full redirect URL, or null if none arrived within [timeout].
  Future<Uri?> authenticate(Uri url,
      {Duration timeout = defaultTimeout}) async {
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      throw Exception("Could not open the sign-in page in the browser");
    }
    return waitForRedirect(timeout: timeout);
  }

  /// Waits for a GET to [path] and answers it with a "you can close this
  /// tab" page. Other requests (e.g. favicon.ico) get a 404.
  Future<Uri?> waitForRedirect({Duration timeout = defaultTimeout}) async {
    try {
      return await _firstRedirect().timeout(timeout);
    } on TimeoutException {
      return null;
    } finally {
      await close();
    }
  }

  Future<Uri?> _firstRedirect() async {
    await for (var request in _server) {
      if (request.method != "GET" || request.uri.path != path) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        continue;
      }

      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.html
        ..write(_donePage);
      await request.response.close();

      return redirectUri.replace(query: request.uri.query);
    }
    return null;
  }

  Future<void> close() => _server.close(force: true);

  static const String _donePage = "<!DOCTYPE html><html><head>"
      "<meta charset=\"utf-8\"><title>Signed in</title></head>"
      "<body style=\"font-family: sans-serif; text-align: center; "
      "margin-top: 20vh\"><p>You can close this tab and return to the app."
      "</p></body></html>";
}
