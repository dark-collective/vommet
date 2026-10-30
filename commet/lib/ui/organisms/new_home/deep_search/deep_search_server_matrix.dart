// Vommet (Deep Search, stage 2): the server search's SDK call: one
// account-wide /search (room events, newest first) for a
// DeepSearchServerController. Everything else is pure Dart in
// deep_search_server.dart.
import 'package:commet/diagnostic/diagnostics.dart';
import 'package:commet/ui/organisms/new_home/deep_search/deep_search_query.dart';
import 'package:commet/ui/organisms/new_home/deep_search/deep_search_server.dart';
import 'package:matrix/matrix.dart' as matrix;

/// Results per server page.
const deepSearchServerPageSize = 50;

/// Diagnostics timer names (shipped in perf_summary as "Deep_search_local"
/// and "Deep_search_server": timings and call counts only).
const deepSearchLocalTimer = "Deep search local";
const deepSearchServerTimer = "Deep search server";

/// Times one local (index) search for perf_summary.
Future<T> deepSearchTimeLocal<T>(Future<T> Function() search) =>
    Diagnostics.general.timeAsync(deepSearchLocalTimer, search);

/// A [DeepSearchServerFetch] on [client]'s /search.
DeepSearchServerFetch deepSearchMatrixFetch(matrix.Client client) {
  return (DeepSearchServerFilter filter, String? nextBatch) =>
      Diagnostics.general.timeAsync(
          deepSearchServerTimer, () => _fetch(client, filter, nextBatch));
}

Future<DeepSearchServerPage> _fetch(matrix.Client client,
    DeepSearchServerFilter filter, String? nextBatch) async {
  final rooms = filter.rooms;
  final response = await client.search(
    matrix.Categories(
      roomEvents: matrix.RoomEventsCriteria(
        searchTerm: filter.searchTerm,
        orderBy: matrix.SearchOrder.recent,
        keys: const [matrix.KeyKind.contentBody],
        filter: matrix.SearchFilter(
          limit: deepSearchServerPageSize,
          senders: filter.senders.isEmpty ? null : filter.senders,
          notSenders: filter.notSenders.isEmpty ? null : filter.notSenders,
          rooms: rooms,
          containsUrl: filter.containsUrl ? true : null,
          types: const ["m.room.message"],
        ),
      ),
    ),
    nextBatch: nextBatch,
  );
  final events = response.searchCategories.roomEvents;
  return DeepSearchServerPage(
    [
      for (final r in events?.results ?? const <matrix.Result>[])
        if (r.result != null)
          DeepSearchServerEvent(r.result?.toJson() ?? const {}, rank: r.rank)
    ],
    nextBatch: events?.nextBatch,
    count: events?.count,
  );
}

/// The post-processing context for [client]: its ignored users, its user
/// id (mentions:me) and the rooms the index covers fully, whose server
/// hits are dropped because the local ones win: [fullyIndexed] (rooms
/// whose RoomCoverage is complete; unencrypted DMs) plus every encrypted
/// room (the server can't search those anyway). A partly indexed
/// unencrypted DM keeps its server hits; the merge dedupes them.
DeepSearchServerContext deepSearchMatrixContext(matrix.Client client,
    {Set<String> fullyIndexed = const {},
    Set<String> redactedIds = const {},
    List<String> myNames = const []}) {
  return DeepSearchServerContext(
    coveredRoomIds: {
      ...fullyIndexed,
      for (final room in client.rooms)
        if (room.encrypted) room.id
    },
    ignoredUsers: client.ignoredUsers.toSet(),
    redactedIds: redactedIds,
    myUserId: client.userID,
    myNames: myNames,
  );
}
