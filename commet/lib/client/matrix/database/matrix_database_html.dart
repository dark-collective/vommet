import 'dart:async';

import 'package:matrix/matrix.dart';

import 'package:universal_html/html.dart' as html;

Future<DatabaseApi> getMatrixDatabaseImplementation(String clientName,
    {bool onDatabaseIsolate = true, bool readOnly = false}) async {
  unawaited(html.window.navigator.storage?.persist());
  var db = await MatrixSdkDatabase.init(clientName);
  await db.open();
  return db;
}

Future<DatabaseApi?> getLegacyMatrixDatabaseImplementation(
    String clientName) async {
  return null;
}
