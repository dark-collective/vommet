// Vommet (issues 602, 611): the encrypted search index on native builds:
// a SQLite file run by its own isolate (SearchIndexWorker).
import 'package:commet/client/matrix/components/encrypted_search_index/search_index_backend.dart';
import 'package:commet/client/matrix/components/encrypted_search_index/search_index_entry.dart';
import 'package:commet/client/matrix/components/encrypted_search_index/search_index_store.dart';
import 'package:commet/client/matrix/components/encrypted_search_index/search_index_worker.dart';
import 'package:commet/security/database_keys.dart';
import 'package:commet/security/key_vault/key_hierarchy.dart';

/// Vommet local data encryption: [account] (the client name) picks the
/// index's key; a plaintext index keeps opening as it is, a new one is
/// created encrypted.
Future<SearchIndexBackend> openSearchIndexBackend(String path,
    {String? ownUserId, required String account}) async {
  final key =
      await DatabaseKeys.forFile(path, DatabaseRole.searchIndex, account);
  try {
    final worker =
        await SearchIndexWorker.spawn(path, ownUserId: ownUserId, key: key);
    SearchIndexWorker? reader;
    try {
      reader = await SearchIndexWorker.spawn(path,
          ownUserId: ownUserId, reader: true, key: key);
    } catch (_) {
      // Searches run on the writer then (behind its writes, as before).
    }
    return WorkerSearchIndexBackend(worker, reader: reader);
  } finally {
    key?.fillRange(0, key.length, 0);
  }
}

class WorkerSearchIndexBackend implements SearchIndexBackend {
  WorkerSearchIndexBackend(this.worker, {this.reader});

  /// Runs [store] in this isolate (unit tests).
  factory WorkerSearchIndexBackend.inProcess(SearchIndexStore store) =>
      WorkerSearchIndexBackend(SearchIndexWorker.inProcess(store));

  final SearchIndexWorker worker;

  /// Vommet Deep Search: a second isolate with a read-only connection, so
  /// searches don't queue behind the backfill's page writes.
  final SearchIndexWorker? reader;

  SearchIndexWorker get _read => reader ?? worker;

  @override
  Future<RoomCoverage> coverage(String roomId) => worker.run(_coverage, roomId);

  @override
  Future<SharedContentCounts> counts(String roomId) =>
      worker.run(_counts, roomId);

  @override
  Future<List<IndexHit>> search(String roomId, IndexQuery query,
          {int? beforeTs, int limit = 500}) =>
      _read.run(_search, (roomId, query, beforeTs, limit));

  @override
  Future<List<IndexHit>> list(String roomId,
          {Set<SharedContentKind> kinds = const {},
          bool linksOnly = false,
          int? beforeTs,
          String? beforeEventId,
          int limit = 100}) =>
      _read.run(
          _list, (roomId, kinds, linksOnly, beforeTs, beforeEventId, limit));

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
  Future<IndexSearchResult> searchAll(IndexQuery query,
          {IndexRanking ranking = const IndexRanking(), int limit = 200}) =>
      _read.run(_searchAll, (query, ranking, limit));

  @override
  Future<IndexCoverageTotals> coverageTotals(List<String> roomIds) =>
      _read.run(_coverageTotals, roomIds);

  @override
  Future<List<String>> roomsPostedIn(String senderId) =>
      _read.run(_roomsPostedIn, senderId);

  @override
  Future<int> migrateStep() => worker.run(_migrateStep, null);

  @override
  Future<void> deleteRoom(String roomId) => worker.run(_deleteRoom, roomId);

  @override
  Future<void> clear() => worker.run(_clear, null);

  @override
  Future<void> close() async {
    await reader?.close();
    await worker.close();
  }
}

// Jobs run in the index isolate (top-level so they can be sent there).

RoomCoverage _coverage(SearchIndexStore s, String roomId) => s.coverage(roomId);

SharedContentCounts _counts(SearchIndexStore s, String roomId) =>
    s.counts(roomId);

List<IndexHit> _search(SearchIndexStore s, (String, IndexQuery, int?, int) a) =>
    s.search(a.$1, a.$2, beforeTs: a.$3, limit: a.$4);

List<IndexHit> _list(SearchIndexStore s,
        (String, Set<SharedContentKind>, bool, int?, String?, int) a) =>
    s.list(a.$1,
        kinds: a.$2,
        linksOnly: a.$3,
        beforeTs: a.$4,
        beforeEventId: a.$5,
        limit: a.$6);

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

IndexSearchResult _searchAll(
        SearchIndexStore s, (IndexQuery, IndexRanking, int) a) =>
    s.searchAll(a.$1, ranking: a.$2, limit: a.$3);

IndexCoverageTotals _coverageTotals(SearchIndexStore s, List<String> ids) =>
    s.coverageTotals(ids);

List<String> _roomsPostedIn(SearchIndexStore s, String senderId) =>
    s.roomsPostedIn(senderId);

int _migrateStep(SearchIndexStore s, Object? _) => s.migrateStep();

void _deleteRoom(SearchIndexStore s, String roomId) => s.deleteRoom(roomId);

void _clear(SearchIndexStore s, Object? _) => s.clear();
