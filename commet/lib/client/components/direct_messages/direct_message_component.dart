import 'package:commet/client/client.dart';
import 'package:commet/client/components/component.dart';
import 'package:commet/utils/notifying_list.dart';

abstract class DirectMessagesInterface {
  INotifyingList<Room> get directMessageRooms;

  INotifyingList<Room> get highlightedRoomsList;
}

abstract class DirectMessagesComponent<T extends Client>
    implements Component<T>, DirectMessagesInterface {
  bool isRoomDirectMessage(Room room);

  String? getDirectMessagePartnerId(Room room);

  /// Open a new direct message with another user
  Future<Room?> createDirectMessage(String userId);

  /// Vommet: the one other person in [room] when it can be marked as a
  /// direct message (exactly one other member); null otherwise.
  String? directMessageCandidate(Room room);

  /// Vommet: mark [room] as a direct message with [directMessageCandidate],
  /// or stop treating it as one. Stored in the account (m.direct), so every
  /// app signed in to it sees the change.
  Future<void> setDirectMessage(Room room, bool isDirectMessage);

  /// Vommet issue 99: every direct message with [userId] on this account,
  /// newest activity first (replaced rooms left out). More than one when
  /// you ended up with several; the lists show only the first.
  List<Room> directMessagesWith(String userId) => const [];

  /// Vommet issue 99: whether [room] is an older direct message with a
  /// person you have a newer one with. The lists leave it out.
  bool isOlderDirectMessage(Room room) => false;
}
