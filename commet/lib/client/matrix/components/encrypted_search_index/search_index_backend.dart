// Vommet (issues 602, 611): what the encrypted search index component needs
// from the index database. Native builds run it in an isolate
// (search_index_backend_io.dart); the web build has none.
import 'package:commet/client/matrix/components/encrypted_search_index/search_index_entry.dart';
import 'package:commet/client/matrix/components/encrypted_search_index/search_index_types.dart';

export 'search_index_backend_stub.dart'
    if (dart.library.io) 'search_index_backend_io.dart'
    show openSearchIndexBackend;

abstract class SearchIndexBackend {
  Future<RoomCoverage> coverage(String roomId);
  Future<SharedContentCounts> counts(String roomId);
  Future<List<IndexHit>> search(String roomId, IndexQuery query,
      {int? beforeTs, int limit = 500});
  Future<List<IndexHit>> list(String roomId,
      {Set<SharedContentKind> kinds = const {},
      bool linksOnly = false,
      int? beforeTs,
      String? beforeEventId,
      int limit = 100});
  Future<void> addTopSegment(String roomId);
  Future<void> addGapSegment(String roomId, String fromToken);
  Future<String?> nextRoom(List<String> roomIds);
  Future<IndexSegment?> nextSegment(String roomId);
  Future<IndexPageResult> applyPage(String roomId, int segmentId,
      List<Map<String, dynamic>> events, String? end,
      {List<Map<String, dynamic>> undecrypted = const []});
  Future<int> addLive(String roomId, List<Map<String, dynamic>> events,
      {int? headTs});
  Future<List<String>> roomsWithUndecrypted();
  Future<List<Map<String, dynamic>>> undecrypted(String roomId);
  Future<int> completeCount(List<String> roomIds);

  /// Deep Search: across rooms, ranked (on the reader connection).
  Future<IndexSearchResult> searchAll(IndexQuery query,
      {IndexRanking ranking = const IndexRanking(), int limit = 200});
  Future<IndexCoverageTotals> coverageTotals(List<String> roomIds);

  /// One step of the v1 → v2 upgrade; how many rows are left.
  Future<int> migrateStep();
  Future<void> deleteRoom(String roomId);
  Future<void> clear();
  Future<void> close();
}
