// Vommet issue 580: the People button under Home on the sidebar rail and
// the list of every direct message it opens. The list logic lives here,
// apart from the widgets, so tests can drive it without a client.
import 'package:commet/client/client.dart';
import 'package:commet/client/components/invitation/invitation.dart';
import 'package:commet/client/components/invitation/invitation_component.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/organisms/home_screen/dm_search.dart';
import 'package:commet/utils/vommet_unread.dart';

class PeopleModel {
  /// Whether the rail shows the People button (on unless hidden from its
  /// menu or in Settings › Appearance).
  static bool get enabled => preferences.peopleInRail.value;

  /// [directMessages] as People lists them: newest first, only [client]'s
  /// when the account filter is on, and only those matching [query] (by
  /// name, Matrix ID or nickname, as the Home list's search).
  static List<Room> rooms(Iterable<Room> directMessages,
      {String query = "", Client? client}) {
    final q = query.trim();
    return [
      for (final room in directMessages)
        if ((client == null || room.client == client) &&
            (q.isEmpty || dmSearchMatches(q, dmSearchNames(room))))
          room
    ]..sort(newestFirst);
  }

  static int newestFirst(Room a, Room b) =>
      b.lastEventTimestamp.compareTo(a.lastEventTimestamp);

  /// The red count on the People button: unread messages across [rooms].
  static int unreadCount(Iterable<Room> rooms, {Client? client}) => rooms
      .where((room) => client == null || room.client == client)
      .fold(0, (sum, room) => sum + room.notificationCount);

  /// Invitations to direct messages ("wants to message you"), with the
  /// account each one belongs to.
  static List<(InvitationComponent, Invitation)> directInvitations(
      Iterable<Client> clients,
      {Client? client}) {
    return [
      for (final c in clients)
        if (client == null || c == client)
          if (c.getComponent<InvitationComponent>() case final component?)
            for (final invite in component.invitations)
              if (invite.isDirect) (component, invite)
    ];
  }

  /// Whether [room] is a group DM (more than one other person in it); its
  /// row shows two pictures.
  static bool isGroup(Room room) => groupMemberIds(room).length > 1;

  /// Up to two other people in [room], for a group DM's double picture.
  static List<String> groupMemberIds(Room room) {
    final self = room.client.self?.identifier;
    return room.memberIds.where((id) => id != self).take(2).toList();
  }

  /// "Mark all as read" on the People button: every DM in [rooms] with
  /// something unread. One room failing doesn't stop the rest.
  static Future<void> markAllRead(Iterable<Room> rooms) async {
    for (final room in rooms.toList()) {
      if (room.notificationCount <= 0 && !roomHasUnread(room)) continue;
      try {
        await room.markAsRead();
      } catch (e, s) {
        Log.onError(e, s);
      }
    }
  }
}
