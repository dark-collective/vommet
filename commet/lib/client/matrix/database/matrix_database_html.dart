import 'dart:async';
import 'dart:js_interop';

import 'package:commet/debug/log.dart';
import 'package:matrix/matrix.dart';
import 'package:web/web.dart' as web;

Future<DatabaseApi> getMatrixDatabaseImplementation(String clientName,
    {bool onDatabaseIsolate = true, bool readOnly = false}) async {
  // Vommet: package:web instead of universal_html (dart:html doesn't build
  // for WebAssembly). Persistent storage keeps the browser from evicting the
  // database (and the crypto keys in it) under storage pressure. Don't wait
  // for it: Firefox asks the user first, and until they answered the
  // database never opened (sign-in spun forever).
  try {
    unawaited(web.window.navigator.storage.persist().toDart.then<void>((_) {},
        onError: (Object e) => Log.w("Persistent storage request failed: $e")));
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
