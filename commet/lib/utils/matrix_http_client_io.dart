import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

http.Client createPlatformHttpClient({required int maxConnectionsPerHost}) {
  // A client given with http.runWithClient (tests) is used as it is.
  final client = http.Client();
  if (client is! IOClient) return client;
  client.close();
  return IOClient(HttpClient()
    ..maxConnectionsPerHost = maxConnectionsPerHost
    // A server that doesn't answer the connection gives its slot back.
    ..connectionTimeout = const Duration(seconds: 30));
}
