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

  /// Vommet: who may post a call membership, which starting or joining needs.
  RoomCallPermissions get permissions;

  /// Vommet: lets everyone at the room's default level join calls (what
  /// Element Call's room setup does). Needs permission to change roles.
  Future<void> letEveryoneJoin();
}

class RoomCallPermissions {
  const RoomCallPermissions(
      {required this.requiredLevel,
      required this.ownLevel,
      required this.canChangePermissions,
      required this.othersBlocked});

  /// The power level a call membership needs.
  final int requiredLevel;
  final int ownLevel;

  /// Whether we may change the room's permissions (power levels).
  final bool canChangePermissions;

  /// Whether some other members can't join a call (below [requiredLevel]).
  final bool othersBlocked;

  bool get canJoin => ownLevel >= requiredLevel;

  /// "moderators (power level 50)", "admins (power level 100)".
  static String levelName(int level) => switch (level) {
        >= 100 => "admins (power level $level)",
        >= 50 => "moderators (power level $level)",
        _ => "power level $level",
      };
}
