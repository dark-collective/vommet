import 'package:commet/client/matrix/components/direct_messages/matrix_direct_chat_ids.dart';
import 'package:commet/utils/bridged_user_rules.dart';
import 'package:matrix/matrix.dart' as matrix;

/// Bridge service accounts are room members, but aren't the person in a DM.
/// Only the room's explicit bridgebot declarations count; bot-like names alone
/// must never hide a real member.
class MatrixBridgedDm {
  static Set<String> bots(matrix.Room room) => {
        for (final type in bridgeStateTypes)
          for (final event in room.states[type]?.values ??
              const <matrix.StrippedStateEvent>[])
            if (event.content['bridgebot'] case final String id)
              if (RegExp(r'^@[^:\s]+:[^\s]+$').hasMatch(id) &&
                  id != room.client.userID)
                id,
      };

  static String? partner(matrix.Room room) {
    if (!MatrixDirectChatIds.mayBeDirectChat(room)) return null;
    final original = room.directChatMatrixID;
    if (original == null) return null;
    final excluded = bots(room);
    if (!excluded.contains(original)) return original;

    final me = room.client.userID;
    final direct = {
      for (final entry in room.client.directChats.entries)
        if (entry.value.contains(room.id) &&
            entry.key != me &&
            !excluded.contains(entry.key))
          entry.key,
    };
    if (direct.length == 1) return direct.single;
    final others = {
      ...?room.summary.mHeroes,
      ...room.getParticipants(
          [matrix.Membership.join, matrix.Membership.invite]).map((u) => u.id),
    }..removeWhere((id) => id == me || excluded.contains(id));
    return others.length == 1 ? others.single : null;
  }

  /// Personal nicknames keep precedence over a portal's explicit room name.
  /// Only inferred names replace the bridge service account with the person.
  static String displayName(matrix.Room room, String person,
      {String? petName}) {
    if (petName != null) return petName;
    final isPortal = bots(room).isNotEmpty;
    if (room.name.isNotEmpty && isPortal) return room.name;
    final member = room.unsafeGetUserFromMemoryOrFallback(person);
    return member.displayName ??
        (isPortal ? member.calcDisplayname() : room.getLocalizedDisplayname());
  }

  static Uri? roomAvatar(matrix.Room room) {
    final url = room.getState(matrix.EventTypes.RoomAvatar)?.content['url'];
    return url is String ? Uri.tryParse(url) : null;
  }

  static Uri? avatar(matrix.Room room) {
    final explicit = roomAvatar(room);
    if (explicit != null) return explicit;
    final person = partner(room);
    return person == null
        ? null
        : room.unsafeGetUserFromMemoryOrFallback(person).avatarUrl;
  }

  /// A server summary includes bridgebots, including in lazy-loaded rooms.
  /// Subtract only bots known to be joined/invited (or listed as heroes).
  static int? activeCount(matrix.Room room, Set<String> excluded) {
    final summary = room.summary;
    if (summary.mJoinedMemberCount == null &&
        summary.mInvitedMemberCount == null) return null;
    final activeBots = excluded.where((id) {
      final membership = room
          .getState(matrix.EventTypes.RoomMember, id)
          ?.content['membership'];
      return membership == 'join' ||
          membership == 'invite' ||
          (membership == null && (summary.mHeroes?.contains(id) ?? false));
    }).length;
    final count = (summary.mJoinedMemberCount ?? 0) +
        (summary.mInvitedMemberCount ?? 0) -
        activeBots;
    return count < 0 ? 0 : count;
  }
}
