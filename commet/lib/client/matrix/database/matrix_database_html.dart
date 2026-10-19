import 'dart:js_interop';

import 'package:commet/debug/log.dart';
import 'package:matrix/matrix.dart';
import 'package:web/web.dart' as web;

Future<DatabaseApi> getMatrixDatabaseImplementation(String clientName,
    {bool onDatabaseIsolate = true, bool readOnly = false}) async {
  // Vommet: package:web instead of universal_html (dart:html doesn't build
  // for WebAssembly). Persistent storage keeps the browser from evicting the
  // database (and the crypto keys in it) under storage pressure.
  try {
    await web.window.navigator.storage.persist().toDart;
  } catch (e) {
    Log.w("Persistent storage request failed: $e");
  }
  var db = await MatrixSdkDatabase.init(clientName);
  await db.open();
  return db;
}

Future<DatabaseApi?> getLegacyMatrixDatabaseImplementation(
    String clientName) async {
  return null;
}
