import 'package:commet/client/client.dart';
import 'package:commet/client/components/room_component.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';

/// Vommet: one page of a room's messages with an attachment, newest first.
class RoomMediaPage {
  const RoomMediaPage(this.events, {this.next});

  final List<TimelineEvent> events;

  /// Where the next (older) page starts; null once the start of the room
  /// is reached.
  final String? next;
}

/// Vommet: pages through only a room's messages that carry a file (pictures,
/// videos, files, voice), filtered by the server, for the member panel's
/// Media and Files tabs. Paging the whole timeline took many slow federated
/// requests per screenful in a chatty room. Only where the server can see
/// the messages (unencrypted rooms).
abstract class RoomMediaHistoryComponent<R extends Client, T extends Room>
    implements RoomComponent<R, T> {
  /// Whether the server can filter this room's messages (it isn't
  /// encrypted).
  bool get available;

  /// The page older than [from] (null: from the newest message).
  Future<RoomMediaPage> loadPage(String? from, {int limit = 50});

  /// Ids of the messages deleted from now on, as they arrive.
  Stream<String> get onRedacted;
}
