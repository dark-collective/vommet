import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/invitation/invitation.dart';
import 'package:commet/client/components/push_notification/notification_content.dart';
import 'package:commet/client/components/push_notification/notification_manager.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/ui/organisms/invitation_view/invite_strings.dart';
import 'package:intl/intl.dart';

/// Vommet issue 550: on desktop, a room invite that arrives while the app is
/// open alerts like a message does. It goes through [NotificationManager],
/// so the notification settings, Do Not Disturb and "In-app notification
/// banners" (banner while focused, else a system notification) apply as they
/// do to messages. Android already shows its own "Room Invite" notification.
class InviteAlerts {
  /// Desktop platforms with a notifier, and the web app (Vommet issue 767).
  static bool get enabled =>
      PlatformUtils.isLinux || PlatformUtils.isWindows || PlatformUtils.isWeb;

  static String get inviteAlertTitle => Intl.message("Room Invite",
      name: "inviteAlertTitle",
      desc:
          "Title of the notification shown when someone invites you to a room");

  static String inviteAlertBody(String user, String room) => Intl.message(
      "$user invited you to $room",
      args: [user, room],
      name: "inviteAlertBody",
      desc:
          "Body of the room invite notification; user is the inviter's name, room the room's name");

  static String inviteBannerInvitedYouTo(String room) => Intl.message(
      "invited you to $room",
      args: [room],
      name: "inviteBannerInvitedYouTo",
      desc:
          "Second line of the in-app banner for a room invite, under the inviter's name; room is the room's name");

  static RoomInviteNotificationContent content(
      Client client, Invitation invitation, String inviterName,
      {String? body}) {
    final roomName = invitation.displayName ?? invitation.roomId;
    return RoomInviteNotificationContent(
      title: inviteAlertTitle,
      content: body ??
          (invitation.isDirect
              ? inviteRowWantsToMessage(inviterName)
              : inviteAlertBody(inviterName, roomName)),
      clientId: client.identifier,
      roomId: invitation.roomId,
      inviterId: invitation.senderId,
      inviterName: inviterName,
      roomName: roomName,
      isDirect: invitation.isDirect,
      roomImage: invitation.avatar,
      roomColor: invitation.color,
      accountLabel: NotificationContent.accountLabelFor(client),
    );
  }

  /// Alerts about [invitation], unless it comes from someone on the block
  /// list ([ignoredUsers]). [body] replaces the usual text (a grouped
  /// space invite, Vommet issue 734).
  static void alert(Client client, Invitation invitation, String inviterName,
      {required List<String> ignoredUsers, String? body}) {
    if (!enabled) return;
    final sender = invitation.senderId;
    if (sender != null && ignoredUsers.contains(sender)) return;
    unawaited(NotificationManager.notify(
        content(client, invitation, inviterName, body: body)));
  }
}
