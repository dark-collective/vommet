import 'package:collection/collection.dart';
import 'package:commet/client/client.dart';
import 'package:commet/client/components/event_search/event_search_component.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/client/matrix/matrix_timeline.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/ui/molecules/timeline_events/timeline_view_entry.dart';
import 'package:commet/utils/attachment_mime.dart';
import 'package:commet/utils/mime.dart';
import 'package:commet/utils/notifying_list.dart';
import 'package:matrix/matrix.dart' as matrix;

class MatrixEncryptedRoomEventSearchSession extends EventSearchSession {
  MatrixTimeline timeline;
  String? currentSearchTerm;
  String? lastPrevBatch;

  MatrixEncryptedRoomEventSearchSession(this.timeline);

  @override
  bool currentlySearching = false;

  List<TimelineEvent<Client>> results = List.empty(growable: true);

  @override
  Stream<List<TimelineEvent<Client>>> startSearch(String searchTerm,
      {String? nextBatch}) async* {
    currentSearchTerm = searchTerm;

    if (nextBatch == null) {
      results = List.empty(growable: true);
    }

    currentlySearching = true;

    var params = MatrixSearchParameters.parse(searchTerm);

    var search = timeline.matrixTimeline!.startSearch(
        searchTerm: searchTerm,
        searchFunc: (ev) => searchFunc(params, ev),
        prevBatch: nextBatch);

    await for (final chunk in search) {
      var result = chunk.$1
          .map((e) => (timeline.room as MatrixRoom).convertEvent(e))
          .toList();

      Map<String, TimelineEvent> m = {};

      for (var event in result) {
        var type = TimelineViewEntryState.eventToDisplayType(event);
        if (type != TimelineEventWidgetDisplayType.hidden) {
          m[event.eventId] = event;
        }
      }

      if (chunk.$2 != null) {
        lastPrevBatch = chunk.$2;
      }

      result = m.values.toList();
      result.sort((a, b) => b.originServerTs.compareTo(a.originServerTs));

      results.addAll(
          result.where((i) => !results.any((e) => i.eventId == e.eventId)));

      yield results;
    }

    currentlySearching = false;
    yield results;
  }

  static bool searchFunc(MatrixSearchParameters params, matrix.Event event) {
    final body = event.plaintextBody.toLowerCase();
    final numMatchingWords =
        params.words.where((w) => body.contains(w.toLowerCase())).length;

    if (params.requireAttachment) {
      if (event.hasAttachment == false) {
        return false;
      }
    }

    if (params.requireImage) {
      // Vommet: AVIF/HEIC shown through their thumbnail count as pictures.
      if (!Mime.imageTypes.contains(AttachmentMime.ofEvent(event)) &&
          !AttachmentMime.showsThumbnailOnlyEvent(event)) {
        return false;
      }
    }

    if (params.requireVideo) {
      if (!Mime.videoTypes.contains(AttachmentMime.ofEvent(event))) {
        return false;
      }
    }

    if (params.requireUrl) {
      if (!(event.plaintextBody.contains("https://") ||
          event.plaintextBody.contains("http://"))) {
        return false;
      }
    }

    if (params.requiredType != null) {
      if (event.type != params.requiredType &&
          event.messageType != params.requiredType) {
        return false;
      }
    }

    if (params.requiredSender != null) {
      if (event.senderId != params.requiredSender) {
        return false;
      }
    }

    if (numMatchingWords < (params.words.length.toDouble() / 2.0)) {
      return false;
    }

    return true;
  }

  @override
  Stream<List<TimelineEvent<Client>>> continueSearch() {
    var token = lastPrevBatch!;
    lastPrevBatch = null;
    return startSearch(currentSearchTerm!, nextBatch: token);
  }

  @override
  bool get canContinueSearch => true;
}

class MatrixSearchParameters {
  bool requireUrl;

  bool requireImage;

  bool requireVideo;

  bool requireAttachment;

  List<String> words;

  String? requiredSender;

  String? requiredType;

  MatrixSearchParameters({
    required this.words,
    this.requireUrl = false,
    this.requireImage = false,
    this.requireVideo = false,
    this.requireAttachment = false,
    this.requiredSender,
    this.requiredType,
  });

  static const String hasLinkString = 'has:link';
  static const String hasImageString = 'has:image';
  static const String hasVideoString = 'has:video';
  static const String hasFileString = 'has:file';

  static MatrixSearchParameters parse(String query) {
    // Split on any whitespace and drop empty words: a trailing or double
    // space (phone keyboards add one after a suggestion) would otherwise
    // leave "", which every message contains.
    var words = query.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

    // Filter keywords are matched case-insensitively, as phone keyboards
    // capitalise the first letter ("From:", "Has:image").
    String? takeValue(String prefix) {
      var match =
          words.where((w) => w.toLowerCase().startsWith(prefix)).firstOrNull;
      if (match == null) return null;
      words.remove(match);
      return match.substring(prefix.length);
    }

    bool takeFlag(String flag) {
      var found = words.any((w) => w.toLowerCase() == flag);
      words.removeWhere((w) => w.toLowerCase() == flag);
      return found;
    }

    String? requiredType = takeValue("type:");
    String? requiredSender = takeValue("from:");

    bool requireUrl = takeFlag(hasLinkString);
    bool requireImage = takeFlag(hasImageString);
    bool requireVideo = takeFlag(hasVideoString);
    bool requireAttachment = takeFlag(hasFileString);

    return MatrixSearchParameters(
      words: words,
      requireUrl: requireUrl,
      requireImage: requireImage,
      requireVideo: requireVideo,
      requireAttachment: requireAttachment,
      requiredSender: requiredSender,
      requiredType: requiredType,
    );
  }
}

class MatrixServerEventSearchSession extends EventSearchSession {
  MatrixTimeline timeline;

  MatrixServerEventSearchSession(this.timeline);

  NotifyingList<TimelineEvent<Client>> events =
      NotifyingList.empty(growable: true);

  late String currentSearchTerm;

  String? nextBatchToken;

  // Vommet: a query with only filters (e.g. just `from:@user:server`) has no
  // words for the server's full-text search, and homeservers return nothing
  // for an empty search term (Vommet issue 601). Such queries scan the room
  // timeline locally instead, like in encrypted rooms.
  MatrixEncryptedRoomEventSearchSession? _localScan;

  static bool needsLocalScan(MatrixSearchParameters parameters) =>
      parameters.words.isEmpty;

  @override
  bool get currentlySearching =>
      _localScan?.currentlySearching ?? _serverSearching;

  bool _serverSearching = false;

  @override
  bool get canContinueSearch =>
      _localScan?.canContinueSearch ?? nextBatchToken != null;

  @override
  Stream<List<TimelineEvent<Client>>> continueSearch() {
    if (_localScan != null) return _localScan!.continueSearch();
    return startSearch(currentSearchTerm, nextBatch: nextBatchToken!);
  }

  @override
  Stream<List<TimelineEvent<Client>>> startSearch(String searchTerm,
      {String? nextBatch}) {
    currentSearchTerm = searchTerm;
    var client = (timeline.client as MatrixClient).matrixClient;

    var parameters = MatrixSearchParameters.parse(searchTerm);

    if (needsLocalScan(parameters)) {
      _localScan = MatrixEncryptedRoomEventSearchSession(timeline);
      return _localScan!.startSearch(searchTerm);
    }
    _localScan = null;

    _serverSearching = true;

    if (nextBatch == null) {
      events = NotifyingList.empty(growable: true);
    }

    var criteria = matrix.RoomEventsCriteria(
      searchTerm: parameters.words.join(" "),
      orderBy: matrix.SearchOrder.recent,
      filter: matrix.SearchFilter(
          rooms: [timeline.room.identifier],
          limit: 20,
          senders: parameters.requiredSender != null
              ? [parameters.requiredSender!]
              : null,
          containsUrl: parameters.requireUrl == true ? true : null),
      includeState: false,
    );

    Log.i("Criteria: ${criteria.toJson()}");

    client
        .search(matrix.Categories(roomEvents: criteria), nextBatch: nextBatch)
        .then((result) {
      _serverSearching = false;

      var resultEvents = result.searchCategories.roomEvents?.results;
      nextBatchToken = result.searchCategories.roomEvents?.nextBatch;

      events.clear();

      if (resultEvents != null) {
        events.addAll(resultEvents
            .where((i) => i.result != null)
            .sorted((a, b) =>
                b.result!.originServerTs.compareTo(a.result!.originServerTs))
            .map((i) => (timeline.room as MatrixRoom).convertEvent(matrix.Event(
                content: i.result!.content,
                type: i.result!.type,
                eventId: i.result!.eventId,
                senderId: i.result!.senderId,
                originServerTs: i.result!.originServerTs,
                room: timeline.matrixTimeline!.room))));
      }

      events.update();
      Log.i("Got events: ${resultEvents}");
    }).catchError((Object e) {
      // Show "no results" instead of searching forever.
      Log.e("Room message search failed: $e");
      _serverSearching = false;
      nextBatchToken = null;
      events.update();
    });

    return events.onListUpdated.map((i) => events);
  }
}

class MatrixEventSearchComponent implements EventSearchComponent<MatrixClient> {
  @override
  MatrixClient client;

  MatrixEventSearchComponent(this.client);

  @override
  Future<EventSearchSession> createSearchSession(Room room) async {
    if (room.isE2EE) {
      var timeline = await room.getTimeline();
      return MatrixEncryptedRoomEventSearchSession(timeline as MatrixTimeline);
    } else {
      var timeline = await room.getTimeline();
      return MatrixServerEventSearchSession(timeline as MatrixTimeline);
    }
  }

  @override
  List<String> getSupportedSearchFeatures(Room room) {
    if (room.isE2EE) {
      return [
        MatrixSearchParameters.hasLinkString,
        MatrixSearchParameters.hasFileString,
        MatrixSearchParameters.hasImageString,
        MatrixSearchParameters.hasVideoString,
        "from:@user:example.com"
      ];
    } else {
      return ["from:@user:example.com"];
    }
  }
}
