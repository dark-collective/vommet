import 'package:commet/client/client.dart';
import 'package:commet/client/components/component.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';

abstract class EventSearchSession {
  Stream<List<TimelineEvent>> startSearch(String searchTerm);

  Stream<List<TimelineEvent>> continueSearch();

  bool get currentlySearching;

  bool get canContinueSearch;

  /// Vommet: the search is closed (its view closed or started a new one).
  /// Releases the room's timeline it held.
  void close() {}

  /// Vommet: whether this session holds a room timeline. One that holds
  /// none (the on-device index) is kept when its chat goes.
  bool get holdsTimeline => true;

  /// Vommet: where [continueSearch] would go on from, so a new session can
  /// pick up there after this one closed; null when there is nowhere.
  String? get resumePoint => null;

  /// Vommet: searches [searchTerm] from [resumePoint] of an older session.
  Stream<List<TimelineEvent>> resumeSearch(String searchTerm, String from) =>
      startSearch(searchTerm);
}

abstract class EventSearchComponent<T extends Client> implements Component<T> {
  Future<EventSearchSession> createSearchSession(Room room);

  List<String> getSupportedSearchFeatures(Room room);
}
