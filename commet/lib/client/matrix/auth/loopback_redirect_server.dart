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
//
// On Linux and Windows flutter_web_auth_2 reports "cancelled" as soon as the
// app regains focus without a redirect, so a browser that failed to start
// (e.g. a stale default-browser entry) ended in "Login Cancelled" with no
// hint why. This server keeps waiting instead, and [pending] lets the UI show
// the sign-in link to copy into any browser, open again, or cancel.
class LoopbackRedirectServer {
  static const Duration defaultTimeout = Duration(minutes: 10);

  /// Whether sign-in uses this instead of flutter_web_auth_2 (desktop).
  static bool get replacesWebAuth =>
      !kIsWeb && (Platform.isMacOS || Platform.isLinux || Platform.isWindows);

  /// The browser sign-in in progress, if any, for the UI to show its link.
  static final ValueNotifier<BrowserSignIn?> pending = ValueNotifier(null);

  final HttpServer _server;
  final String path;
  final Completer<Uri?> _cancelled = Completer();

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
  /// the full redirect URL, or null if none arrived within [timeout] or the
  /// user cancelled. A browser that fails to open is not an error: the link
  /// stays in [pending] for the user to copy.
  Future<Uri?> authenticate(Uri url,
      {Duration timeout = defaultTimeout,
      Future<bool> Function(Uri url)? launch}) async {
    launch ??= _launch;
    var signIn = BrowserSignIn._(url, this, launch);
    pending.value = signIn;
    try {
      signIn._browserOpened.value = await launch(url);
      return await waitForRedirect(timeout: timeout);
    } finally {
      if (pending.value == signIn) pending.value = null;
    }
  }

  static Future<bool> _launch(Uri url) async {
    try {
      return await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      return false;
    }
  }

  /// Stops waiting; [waitForRedirect] then returns null.
  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete(null);
  }

  /// Waits for a GET to [path] and answers it with a "you can close this
  /// tab" page. Other requests (e.g. favicon.ico) get a 404.
  Future<Uri?> waitForRedirect({Duration timeout = defaultTimeout}) async {
    try {
      return await Future.any([_firstRedirect(), _cancelled.future])
          .timeout(timeout);
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

/// A sign-in page that should be open in the browser, for the UI to offer
/// its link when the browser doesn't show up.
class BrowserSignIn {
  final Uri url;
  final LoopbackRedirectServer _server;
  final Future<bool> Function(Uri url) _launch;

  /// Null while the browser is being opened, then whether it was.
  final ValueNotifier<bool?> _browserOpened = ValueNotifier(null);

  BrowserSignIn._(this.url, this._server, this._launch);

  ValueListenable<bool?> get browserOpened => _browserOpened;

  /// Tries the browser again.
  Future<void> reopen() async {
    _browserOpened.value = await _launch(url);
  }

  void cancel() => _server.cancel();
}
