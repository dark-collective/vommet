import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Custom themes kept in the browser, by theme name. Each of a theme's files
/// (theme.json, a background image) is one IndexedDB record keyed
/// `<theme name>/<file name>`; theme names never contain a slash.
class WebThemeStore {
  static const _dbName = "vommet_themes";
  static const _storeName = "files";

  static Future<web.IDBDatabase>? _db;

  static Future<web.IDBDatabase> _open() => _db ??= () {
        final done = Completer<web.IDBDatabase>();
        final request = web.window.indexedDB.open(_dbName, 1);
        request.onupgradeneeded = ((web.Event _) {
          (request.result as web.IDBDatabase).createObjectStore(_storeName);
        }).toJS;
        request.onsuccess = ((web.Event _) {
          done.complete(request.result as web.IDBDatabase);
        }).toJS;
        request.onerror = ((web.Event _) {
          _db = null;
          done.completeError(
              StateError("Could not open theme storage: ${request.error}"));
        }).toJS;
        return done.future;
      }();

  static web.IDBKeyRange _range(String name) =>
      web.IDBKeyRange.bound("$name/".toJS, "$name/￿".toJS);

  static Future<JSAny?> _result(web.IDBRequest request) {
    final done = Completer<JSAny?>();
    request.onsuccess = ((web.Event _) => done.complete(request.result)).toJS;
    request.onerror = ((web.Event _) => done.completeError(
        StateError("Theme storage request failed: ${request.error}"))).toJS;
    return done.future;
  }

  static Future<void> _complete(web.IDBTransaction transaction) {
    final done = Completer<void>();
    transaction.oncomplete = ((web.Event _) => done.complete()).toJS;
    void fail(web.Event _) {
      if (!done.isCompleted) {
        done.completeError(
            StateError("Theme storage write failed: ${transaction.error}"));
      }
    }

    transaction.onerror = fail.toJS;
    transaction.onabort = fail.toJS;
    return done.future;
  }

  static Future<web.IDBObjectStore> _store(String mode) async {
    final db = await _open();
    return db.transaction(_storeName.toJS, mode).objectStore(_storeName);
  }

  static Future<List<String>> names() async {
    final store = await _store("readonly");
    final keys = await _result(store.getAllKeys());
    final names = <String>{};
    for (final key in (keys as JSArray<JSString>).toDart) {
      final k = key.toDart;
      final slash = k.indexOf("/");
      if (slash > 0) names.add(k.substring(0, slash));
    }
    return names.toList()..sort();
  }

  static Future<Map<String, Uint8List>> files(String name) async {
    final store = await _store("readonly");
    // Both requests go out before either is awaited: a transaction closes
    // once it has nothing left to do.
    final keys = _result(store.getAllKeys(_range(name)));
    final values = _result(store.getAll(_range(name)));
    final k = ((await keys) as JSArray<JSString>).toDart;
    final v = ((await values) as JSArray<JSUint8Array>).toDart;
    return {
      for (var i = 0; i < k.length && i < v.length; i++)
        k[i].toDart.substring(name.length + 1): v[i].toDart,
    };
  }

  /// Replaces every file of the theme [name] with [files].
  static Future<void> put(String name, Map<String, Uint8List> files) async {
    final db = await _open();
    final transaction = db.transaction(_storeName.toJS, "readwrite");
    final store = transaction.objectStore(_storeName);
    store.delete(_range(name));
    for (final entry in files.entries) {
      store.put(entry.value.toJS, "$name/${entry.key}".toJS);
    }
    await _complete(transaction);
  }

  static Future<void> remove(String name) async {
    final db = await _open();
    final transaction = db.transaction(_storeName.toJS, "readwrite");
    transaction.objectStore(_storeName).delete(_range(name));
    await _complete(transaction);
  }
}
