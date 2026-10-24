import 'matrix_database_stub.dart'
    // Vommet: dart.library.html is false under WebAssembly; js_interop is
    // set on both web compilers.
    if (dart.library.js_interop) "matrix_database_html.dart"
    if (dart.library.io) "matrix_database_io.dart";

import 'package:matrix/matrix.dart';

Future<DatabaseApi> getMatrixDatabase(String clientName,
    {bool onDatabaseIsolate = true, bool readOnly = false}) {
  return getMatrixDatabaseImplementation(clientName,
      onDatabaseIsolate: onDatabaseIsolate, readOnly: readOnly);
}

Future<DatabaseApi?> getLegacyMatrixDatabase(String clientName) {
  return getLegacyMatrixDatabaseImplementation(clientName);
}
