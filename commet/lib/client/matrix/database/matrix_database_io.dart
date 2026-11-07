import 'dart:io';
import 'dart:typed_data';

import 'package:commet/config/app_config.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/diagnostic/diagnostics.dart';
import 'package:commet/security/database_keys.dart';
import 'package:commet/security/key_vault/key_hierarchy.dart';
import 'package:commet/utils/database/encrypted_open.dart';
import 'package:commet/utils/database/multiple_database_server.dart';
import 'package:drift/native.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix_dart_sdk_drift_db/matrix_dart_sdk_drift_db.dart';
import 'package:path/path.dart' as p;

Future<DatabaseApi> getMatrixDatabaseImplementation(String clientName,
    {bool onDatabaseIsolate = true, bool readOnly = false}) async {
  var path = await AppConfig.getDriftDatabasePath();
  path = p.join(path, clientName, "data.db");
  var dir = p.dirname(path);

  if (!await Directory(dir).exists()) {
    await Directory(dir).create(recursive: true);
  }

  final file = File(path);
  // Vommet: local data encryption. A plaintext data.db keeps opening as
  // it is; a new one is created encrypted.
  final key = await DatabaseKeys.forFile(
      file.absolute.path, DatabaseRole.data, clientName,
      readOnly: readOnly);

  try {
    if (onDatabaseIsolate) {
      var connection = await DatabaseIsolate.connect(file.absolute.path,
          readOnly: readOnly, key: key);

      return MatrixSdkDriftDatabase.init(connection, clientName,
          benchmark: benchmarkFunc);
    } else {
      var connection = setupNativeDatabase(file, readOnly: readOnly, key: key);
      return MatrixSdkDriftDatabase.init(connection, clientName,
          benchmark: benchmarkFunc);
    }
  } finally {
    key?.fillRange(0, key.length, 0);
  }
}

/// Opens a database file for drift, keyed with [key] when it is encrypted
/// (see [EncryptedOpen]). Throws [DatabaseKeyError] when the key doesn't
/// open it.
NativeDatabase setupNativeDatabase(File file,
    {bool readOnly = false, Uint8List? key}) {
  // The path only: never the key.
  Log.d("Opening database (readonly: $readOnly, encrypted: ${key != null}) "
      "${file.path}");

  final db = EncryptedOpen.open(file.path, key: key, readOnly: readOnly);

  return NativeDatabase.opened(
    db,
    setup: (database) {
      if (!readOnly) {
        database.execute("pragma journal_mode = wal;");
      }
      // Encrypted pages are decrypted on every cache miss: a bigger page
      // cache (16 MiB) keeps the hot ones decrypted.
      if (key != null) database.execute("pragma cache_size = -16000;");
    },
  );
}

Future<T> benchmarkFunc<T>(String name, Future<T> Function() func,
    [int? itemCount]) {
  return Diagnostics.databaseDiagnostics.timeAsync(name, func);
}

Future<DatabaseApi?> getLegacyMatrixDatabaseImplementation(
    String clientName) async {
  return null;
}
