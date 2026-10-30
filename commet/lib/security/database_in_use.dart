// Vommet: local data encryption, which database files an engine of this
// process has opened (or is opening), so the migration never swaps a file
// out from under one.
//
// Android runs the UI engine and headless push engines in one process and
// they share the database isolate, which keeps connections open by path.
// Every engine marks a path here before it reads the file's state; the
// migration first records the state "migrating" in keystore.json, then
// checks the mark, and skips a marked file for this run. Whichever comes
// second sees the other: an engine that marks after the check finds
// "migrating" and doesn't open the file (see DatabaseKeys.forFile).
//
// A mark lasts as long as the process (the connection may stay cached that
// long). Other processes are kept out by the single-instance lock on
// desktop and by keystore.json's state.
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' show IsolateNameServer;

import 'package:path/path.dart' as p;

class DatabaseInUse {
  static final Map<String, RawReceivePort> _ports = {};

  static String _name(String path) =>
      "vommet.db.in-use:${p.normalize(File(path).absolute.path)}";

  /// Marks [path] as opened by an engine of this process.
  static void mark(String path) {
    final name = _name(path);
    if (IsolateNameServer.lookupPortByName(name) != null) return;
    final port = RawReceivePort()..keepIsolateAlive = false;
    if (IsolateNameServer.registerPortWithName(port.sendPort, name)) {
      _ports[name] = port;
    } else {
      port.close();
    }
  }

  /// Whether an engine of this process marked [path].
  static bool isInUse(String path) =>
      IsolateNameServer.lookupPortByName(_name(path)) != null;

  /// For tests: forgets the marks this isolate made.
  static void debugClear() {
    for (final entry in _ports.entries) {
      IsolateNameServer.removePortNameMapping(entry.key);
      entry.value.close();
    }
    _ports.clear();
  }
}
