// Vommet (issues 602, 611): runs the encrypted search index's database in
// its own isolate, so storing pages and searching never block the UI.
import 'dart:async';
import 'dart:isolate';

import 'package:commet/client/matrix/components/encrypted_search_index/search_index_store.dart';

/// A job for the index isolate. Must be a top-level or static function, so
/// it can be sent there; [A] and the result must be plain data.
typedef SearchIndexJob<A, R> = R Function(SearchIndexStore store, A arg);

class SearchIndexWorker {
  SearchIndexWorker._(this._send, this._isolate, this._store);

  final SendPort? _send;
  final Isolate? _isolate;

  /// Set when running in this isolate ([inProcess], unit tests).
  final SearchIndexStore? _store;
  bool _closed = false;

  /// Opens (or creates) the index at [path] in a new isolate.
  static Future<SearchIndexWorker> spawn(String path) async {
    final ready = ReceivePort();
    final isolate = await Isolate.spawn(_main, (ready.sendPort, path),
        debugName: "encrypted search index");
    final first = await ready.first;
    ready.close();
    if (first is! SendPort) {
      isolate.kill();
      throw StateError("Search index failed to open: $first");
    }
    return SearchIndexWorker._(first, isolate, null);
  }

  /// Runs jobs on [store] in this isolate (tests).
  factory SearchIndexWorker.inProcess(SearchIndexStore store) =>
      SearchIndexWorker._(null, null, store);

  Future<R> run<A, R>(SearchIndexJob<A, R> job, A arg) async {
    if (_closed) throw StateError("Search index is closed");
    final store = _store;
    if (store != null) return job(store, arg);

    final reply = ReceivePort();
    _send!.send((reply.sendPort, job, arg));
    final result = await reply.first as (bool, Object?);
    reply.close();
    if (!result.$1) throw SearchIndexException(result.$2.toString());
    return result.$2 as R;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final store = _store;
    if (store != null) {
      store.dispose();
      return;
    }
    final done = ReceivePort();
    _isolate!.addOnExitListener(done.sendPort);
    _send!.send(null);
    await done.first.timeout(const Duration(seconds: 5), onTimeout: () {
      _isolate.kill(priority: Isolate.immediate);
    });
    done.close();
  }

  static void _main((SendPort, String) args) {
    final (ready, path) = args;
    final SearchIndexStore store;
    try {
      store = SearchIndexStore.open(path);
    } catch (e) {
      ready.send("$e");
      return;
    }
    final port = ReceivePort();
    ready.send(port.sendPort);
    port.listen((message) {
      if (message == null) {
        store.dispose();
        port.close();
        return;
      }
      final (SendPort reply, Function job, Object? arg) =
          message as (SendPort, Function, Object?);
      try {
        reply.send((true, job(store, arg)));
      } catch (e, s) {
        reply.send((false, "$e\n$s"));
      }
    });
  }
}

class SearchIndexException implements Exception {
  SearchIndexException(this.message);
  final String message;
  @override
  String toString() => "SearchIndexException: $message";
}
