// Vommet: the http client each Matrix account talks to its server with.
//
// dart:io's HttpClient opens a new connection for every request that finds
// none free, without limit. On a large account the start sent hundreds of
// profile, member and thumbnail requests at once: as many sockets (each a
// TLS handshake on the main isolate), all timing out together, and near
// the default 1,024 open-file limit of many Linux desktops. The SDK and the
// image loader now send only a few of each kind at a time; this caps what
// is left as a safety net, well above that.
import 'package:http/http.dart' as http;

import 'package:commet/utils/matrix_http_client_stub.dart'
    if (dart.library.io) 'package:commet/utils/matrix_http_client_io.dart';

/// Most connections to one server at once.
const int matrixMaxConnectionsPerHost = 64;

http.Client createMatrixHttpClient() => createPlatformHttpClient(
    maxConnectionsPerHost: matrixMaxConnectionsPerHost);
