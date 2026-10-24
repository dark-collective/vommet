// Vommet: the http client of a Matrix account opens at most a few
// connections to one server (dart:io's had no limit). Without the Flutter
// test binding, whose HttpOverrides would replace the real HttpClient.
import 'package:commet/utils/matrix_http_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:http/testing.dart';

void main() {
  test("the account's http client keeps a client given for tests", () {
    final mock = MockClient((_) async => http.Response("", 200));
    expect(http.runWithClient(createMatrixHttpClient, () => mock), same(mock));
    final real = createMatrixHttpClient();
    expect(real, isA<IOClient>());
    real.close();
    expect(matrixMaxConnectionsPerHost, inInclusiveRange(8, 64));
  });
}
