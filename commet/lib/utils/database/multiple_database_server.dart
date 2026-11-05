import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:commet/client/matrix/database/matrix_database_io.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/utils/database/encrypted_open.dart';
import 'package:drift/drift.dart';
import 'package:drift/isolate.dart';

/// Vommet: the database isolate. A connect message is
/// `[path, SendPort, readOnly, TransferableTypedData? key]`: the file is
/// opened (and keyed) before the connect port is sent back, so a wrong or
/// missing key reaches the caller as `["error", kind, message]` instead of
/// leaving it waiting. A failed open isn't cached. The isolate only ever
/// gets per-file keys, never the master key.
final class MultiDatabaseServer {
  final Map<String, DriftIsolate> _activeIsolates = {};
  final ReceivePort _receiveConnections = ReceivePort();

  MultiDatabaseServer() {
    _receiveConnections.listen((message) {
      if (message is! List) {
        Log.e("Expected to receive a list");
        return;
      }

      if (message.length != 4) {
        Log.e("Received list of incorrect length");
        return;
      }

      final name = message[0];
      final port = message[1];
      final readOnly = message[2] as bool;
      final keyData = message[3];

      if (name is! String) {
        Log.e("list[0] was not a string");
        return;
      }

      if (port is! SendPort) {
        Log.e("list[1] was not a SendPort");
        return;
      }

      final key = keyData is TransferableTypedData
          ? keyData.materialize().asUint8List()
          : null;

      try {
        var isolate = _activeIsolates[name];
        if (isolate == null) {
          final database =
              setupNativeDatabase(File(name), readOnly: readOnly, key: key);
          isolate = DriftIsolate.inCurrent(serialize: true, () => database);
          _activeIsolates[name] = isolate;
        }
        port.send(isolate.connectPort);
      } on DatabaseKeyError catch (e) {
        Log.w("Couldn't open a database: $e");
        port.send(["error", e.kind.name, e.message]);
      } catch (e) {
        // Not the exception itself: its message could quote a statement.
        Log.w("Couldn't open a database: ${e.runtimeType} ($name)");
        port.send(["error", "open", "${e.runtimeType}"]);
      } finally {
        key?.fillRange(0, key.length, 0);
      }
    });
  }
}

class DatabaseIsolate {
  static final receiveConnectPort = ReceivePort();
  static SendPort? connectToServer;
  static const isolateName = "im.nether.chat.database_isolate";

  static Future<void> start() async {
    connectToServer = IsolateNameServer.lookupPortByName(isolateName);
    if (connectToServer == null) {
      Isolate.spawn(
        (SendPort port) {
          final server = MultiDatabaseServer();
          port.send(server._receiveConnections.sendPort);
        },
        receiveConnectPort.sendPort,
        debugName: "Database Isolate",
      );

      connectToServer = await receiveConnectPort.first as SendPort;
      IsolateNameServer.registerPortWithName(connectToServer!, isolateName);
    }
  }

  /// Connects to [databaseName] (a path) on the database isolate, keyed
  /// with [key] when it is encrypted. Throws [DatabaseKeyError] when the
  /// key doesn't open it, [DatabaseOpenError] when it fails otherwise.
  static Future<DatabaseConnection> connect(String databaseName,
      {bool readOnly = false, Uint8List? key}) async {
    if (connectToServer == null) {
      await start();
    }

    final response = ReceivePort();

    connectToServer!.send([
      databaseName,
      response.sendPort,
      readOnly,
      key == null ? null : TransferableTypedData.fromList([key]),
    ]);

    final reply = await response.first;
    if (reply is List && reply.length == 3 && reply[0] == "error") {
      final kind = DatabaseKeyErrorKind.values
          .where((k) => k.name == reply[1])
          .firstOrNull;
      if (kind != null) {
        throw DatabaseKeyError(kind, reply[2] as String, path: databaseName);
      }
      throw DatabaseOpenError(reply[2] as String, databaseName);
    }
    final connectPort = reply as SendPort;
    return DriftIsolate.fromConnectPort(connectPort, serialize: true).connect();
  }
}

/// The database isolate couldn't open a file (not a key problem).
class DatabaseOpenError implements Exception {
  DatabaseOpenError(this.message, this.path);
  final String message;
  final String path;

  @override
  String toString() => "DatabaseOpenError: $message ($path)";
}
