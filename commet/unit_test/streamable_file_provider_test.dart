import 'package:commet/cache/streamable_file_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  setUp(resetRangeSupportCache);

  MockClient server(int status, List<http.Request> seen) =>
      MockClient((request) async {
        seen.add(request);
        return http.Response(status == 206 ? "x" : "whole file", status);
      });

  test("a server that answers the range can be streamed from", () async {
    final seen = <http.Request>[];
    final uri =
        Uri.parse("https://a.example/_matrix/client/v1/media/download/x");

    expect(
        await serverSupportsRangeRequests(server(206, seen), uri,
            headers: {"authorization": "Bearer t"}),
        isTrue);
    expect(seen.single.headers["range"], "bytes=0-0");
    expect(seen.single.headers["authorization"], "Bearer t");
  });

  test("a server that ignores the range can't, and is asked only once",
      () async {
    final seen = <http.Request>[];
    final client = server(200, seen);

    expect(
        await serverSupportsRangeRequests(
            client, Uri.parse("https://b.example/one")),
        isFalse);
    expect(
        await serverSupportsRangeRequests(
            client, Uri.parse("https://b.example/two")),
        isFalse);
    expect(seen, hasLength(1));
  });

  test("an error answer is not remembered", () async {
    final seen = <http.Request>[];
    final uri = Uri.parse("https://c.example/missing");

    expect(await serverSupportsRangeRequests(server(404, seen), uri), isFalse);
    expect(await serverSupportsRangeRequests(server(206, seen), uri), isTrue);
  });
}
