import 'package:http/http.dart' as http;

/// The web version: the browser pools connections itself.
http.Client createPlatformHttpClient({required int maxConnectionsPerHost}) =>
    http.Client();
