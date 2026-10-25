// Vommet (issues 602, 611): the encrypted search index on native builds:
// a SQLite file run by its own isolate (SearchIndexWorker).
import 'package:commet/client/matrix/components/encrypted_search_index/search_index_backend.dart';
import 'package:commet/client/matrix/components/encrypted_search_index/search_index_entry.dart';
import 'package:commet/client/matrix/components/encrypted_search_index/search_index_store.dart';
import 'package:commet/client/matrix/components/encrypted_search_index/search_index_worker.dart';

Future<SearchIndexBackend> openSearchIndexBackend(String path) async =>
    WorkerSearchIndexBackend(await SearchIndexWorker.spawn(path));

class WorkerSearchIndexBackend implements SearchIndexBackend {
  WorkerSearchIndexBackend(this.worker);

  /// Runs [store] in this isolate (unit tests).
  factory WorkerSearchIndexBackend.inProcess(SearchIndexStore store) =>
      WorkerSearchIndexBackend(SearchIndexWorker.inProcess(store));

  final SearchIndexWorker worker;

  @override
  Future<RoomCoverage> coverage(String roomId) => worker.run(_coverage, roomId);

  @override
  Future<SharedContentCounts> counts(String roomId) =>
      worker.run(_counts, roomId);

  @override
  Future<List<IndexHit>> search(String roomId, IndexQuery query,
          {int? beforeTs, int limit = 500}) =>
      worker.run(_search, (roomId, query, beforeTs, limit));

  @override
  Future<List<IndexHit>> list(String roomId,
          {Set<SharedContentKind> kinds = const {},
          bool linksOnly = false,
          int? beforeTs,
          int limit = 100}) =>
      worker.run(_list, (roomId, kinds, linksOnly, beforeTs, limit));

  @override
  Future<void> addTopSegment(String roomId) =>
      worker.run(_addTopSegment, roomId);

  @override
  Future<void> addGapSegment(String roomId, String fromToken) =>
      worker.run(_addGapSegment, (roomId, fromToken));

  @override
  Future<String?> nextRoom(List<String> roomIds) =>
      worker.run(_nextRoom, roomIds);

  @override
  Future<IndexSegment?> nextSegment(String roomId) =>
      worker.run(_nextSegment, roomId);

  @override
  Future<IndexPageResult> applyPage(String roomId, int segmentId,
          List<Map<String, dynamic>> events, String? end,
          {List<Map<String, dynamic>> undecrypted = const []}) =>
      worker.run(_applyPage, (roomId, segmentId, events, end, undecrypted));

  @override
  Future<int> addLive(String roomId, List<Map<String, dynamic>> events,
          {int? headTs}) =>
      worker.run(_addLive, (roomId, events, headTs));

  @override
  Future<List<String>> roomsWithUndecrypted() =>
      worker.run(_roomsWithUndecrypted, null);

  @override
  Future<List<Map<String, dynamic>>> undecrypted(String roomId) =>
      worker.run(_undecrypted, roomId);

  @override
  Future<int> completeCount(List<String> roomIds) =>
      worker.run(_completeCount, roomIds);

  @override
  Future<void> deleteRoom(String roomId) => worker.run(_deleteRoom, roomId);

  @override
  Future<void> clear() => worker.run(_clear, null);

  @override
  Future<void> close() => worker.close();
}

// Jobs run in the index isolate (top-level so they can be sent there).

RoomCoverage _coverage(SearchIndexStore s, String roomId) => s.coverage(roomId);

SharedContentCounts _counts(SearchIndexStore s, String roomId) =>
    s.counts(roomId);

List<IndexHit> _search(SearchIndexStore s, (String, IndexQuery, int?, int) a) =>
    s.search(a.$1, a.$2, beforeTs: a.$3, limit: a.$4);

List<IndexHit> _list(SearchIndexStore s,
        (String, Set<SharedContentKind>, bool, int?, int) a) =>
    s.list(a.$1, kinds: a.$2, linksOnly: a.$3, beforeTs: a.$4, limit: a.$5);

void _addTopSegment(SearchIndexStore s, String roomId) =>
    s.addTopSegment(roomId);

void _addGapSegment(SearchIndexStore s, (String, String) a) =>
    s.addGapSegment(a.$1, a.$2);

String? _nextRoom(SearchIndexStore s, List<String> roomIds) =>
    s.nextRoom(roomIds);

IndexSegment? _nextSegment(SearchIndexStore s, String roomId) =>
    s.nextSegment(roomId);

IndexPageResult _applyPage(
        SearchIndexStore s,
        (
          String,
          int,
          List<Map<String, dynamic>>,
          String?,
          List<Map<String, dynamic>>
        ) a) =>
    s.applyPage(a.$1, a.$2, a.$3, a.$4, undecrypted: a.$5);

int _addLive(
        SearchIndexStore s, (String, List<Map<String, dynamic>>, int?) a) =>
    s.addLive(a.$1, a.$2, headTs: a.$3);

List<String> _roomsWithUndecrypted(SearchIndexStore s, Object? _) =>
    s.roomsWithUndecrypted();

List<Map<String, dynamic>> _undecrypted(SearchIndexStore s, String roomId) =>
    s.undecrypted(roomId);

int _completeCount(SearchIndexStore s, List<String> roomIds) =>
    s.completeCount(roomIds);

void _deleteRoom(SearchIndexStore s, String roomId) => s.deleteRoom(roomId);

void _clear(SearchIndexStore s, Object? _) => s.clear();
