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
}
