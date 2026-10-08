import 'package:commet/client/client.dart';
import 'package:commet/client/components/room_component.dart';
import 'package:commet/client/components/voip/voip_session.dart';

/// Vommet: a call running in an ordinary (non-voice) room, such as one
/// started from Element or Element X in a group chat or DM. Voice rooms keep
/// using VoipRoomComponent; this one exists on every other room so the chat
/// view can offer to join.
abstract class RoomCallComponent<R extends Client, T extends Room>
    implements RoomComponent<R, T> {
  /// Users with a live call membership in the room.
  List<String> getCurrentParticipants();

  Stream<void> get onParticipantsChanged;

  bool get canJoinCall;

  Future<VoipSession?> joinCall();

  /// Joins, and if nobody was in the call yet, tells the room a call started
  /// (Element rings DMs and shows the call in group chats).
  Future<VoipSession?> startCall();
}
