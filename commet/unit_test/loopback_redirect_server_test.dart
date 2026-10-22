import 'dart:io';

import 'package:commet/client/matrix/auth/loopback_redirect_server.dart';
import 'package:flutter_test/flutter_test.dart';

Future<int> _get(Uri uri) async {
  var client = HttpClient();
  try {
    var response = await (await client.getUrl(uri)).close();
    await response.drain<void>();
    return response.statusCode;
  } finally {
    client.close(force: true);
  }
}

void main() {
  test('returns the redirect with its query and ignores other paths', () async {
    var server = await LoopbackRedirectServer.bind("/oauth/callback");
    var base = server.redirectUri;
    expect(base.toString(), "http://127.0.0.1:${server.port}/oauth/callback");

    var redirect = server.waitForRedirect();

    expect(await _get(base.replace(path: "/favicon.ico")), 404);
    expect(await _get(base.replace(query: "code=abc&state=xyz")), 200);

    var result = await redirect;
    expect(result?.path, "/oauth/callback");
    expect(result?.port, base.port);
    expect(result?.queryParameters, {"code": "abc", "state": "xyz"});
  });

  test('gives up after the timeout and frees the port', () async {
    var server = await LoopbackRedirectServer.bind("/login");
    var port = server.port;

    expect(
        await server.waitForRedirect(timeout: const Duration(milliseconds: 50)),
        isNull);

    var socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
    await socket.close();
  });

  test('keeps waiting when the browser fails to open, until cancelled',
      () async {
    var server = await LoopbackRedirectServer.bind("/oauth/callback");
    var url = Uri.parse("https://example.org/auth");

    var result = server.authenticate(url, launch: (_) async => false);
    await Future<void>.delayed(Duration.zero);

    var signIn = LoopbackRedirectServer.pending.value;
    expect(signIn?.url, url);
    expect(signIn?.browserOpened.value, isFalse);

    signIn!.cancel();
    expect(await result, isNull);
    expect(LoopbackRedirectServer.pending.value, isNull);
  });

  test('offers the link while waiting and clears it after the redirect',
      () async {
    var server = await LoopbackRedirectServer.bind("/oauth/callback");
    var launches = 0;

    var result = server.authenticate(Uri.parse("https://example.org/auth"),
        launch: (_) async {
      launches++;
      return true;
    });
    await Future<void>.delayed(Duration.zero);

    var signIn = LoopbackRedirectServer.pending.value!;
    expect(signIn.browserOpened.value, isTrue);
    await signIn.reopen();
    expect(launches, 2);

    expect(await _get(server.redirectUri.replace(query: "code=abc")), 200);
    expect((await result)?.queryParameters, {"code": "abc"});
    expect(LoopbackRedirectServer.pending.value, isNull);
  });
}
