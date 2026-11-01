// Vommet: inviting someone straight into a room (not through a space) says
// whether the room's earlier messages go along with the invite (MSC4268),
// in the same words as the space invite dialog, and lets you keep them back.
// Vommet issue 437.

import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/invitation/invitation_component.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/ui/molecules/profile/mini_profile_view.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/organisms/invitation_view/space_invite_dialog.dart';
import 'package:commet/utils/common_strings.dart';
import 'package:commet/utils/space_hierarchy/invite_plan.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:tiamat/tiamat.dart' as tiamat;

class DirectInviteDialog extends StatefulWidget {
  const DirectInviteDialog(
      {required this.client,
      required this.userId,
      required this.roomName,
      required this.history,
      required this.firstContact,
      super.key});

  final Client client;
  final String userId;
  final String roomName;
  final InviteHistory history;
  final bool firstContact;

  static String get directInviteTitle => Intl.message("Invitation",
      name: "directInviteTitle",
      desc: "Dialog for inviting someone to a room: title");

  static String get directInviteConfirm => Intl.message("Invite",
      name: "directInviteConfirm",
      desc:
          "Dialog for inviting someone to a room: button that sends the invite");

  static String directInviteTo(String room) => Intl.message("Invite to $room",
      args: [room],
      name: "directInviteTo",
      desc:
          "Dialog for inviting someone to a room: line naming the room; room is its name");

  static String get directInviteHistoryIncluded => Intl.message(
      "History included",
      name: "directInviteHistoryIncluded",
      desc:
          "Dialog for inviting someone to a room: status chip when the invitee will be able to read the room's earlier messages");

  static String get directInviteNewMessagesOnly => Intl.message(
      "New messages only",
      name: "directInviteNewMessagesOnly",
      desc:
          "Dialog for inviting someone to a room: status chip when the invitee will only see new messages");

  static String get directInviteNotEncrypted => Intl.message("Not encrypted",
      name: "directInviteNotEncrypted",
      desc:
          "Dialog for inviting someone to a room: status chip when the room isn't encrypted");

  static String get directInviteShareHistory => Intl.message(
      "Share earlier messages",
      name: "directInviteShareHistory",
      desc:
          "Dialog for inviting someone to a room: tick box to send the invitee the keys to the room's earlier messages");

  static String directInviteShareHistoryDescription(String userId) => Intl.message(
      "Sends $userId the keys to messages from before the invite. Untick to share only new messages.",
      args: [userId],
      name: "directInviteShareHistoryDescription",
      desc:
          "Dialog for inviting someone to a room: explanation under the share earlier messages tick box; userId is the invitee's Matrix ID");

  static String get directInviteNewMessagesOnlyNote => Intl.message(
      "This room's history setting only lets new members read messages sent after they join, so earlier messages won't be shared. You can change it in the room's settings, under Permissions, History Visibility.",
      name: "directInviteNewMessagesOnlyNote",
      desc:
          "Dialog for inviting someone to a room: explanation when the room's earlier messages won't be shared");

  static String get directInviteNotEncryptedNote => Intl.message(
      "The server shows earlier messages as the room's history setting says.",
      name: "directInviteNotEncryptedNote",
      desc:
          "Dialog for inviting someone to a room: explanation when the room isn't encrypted");

  static String directInviteFirstContact(String userId) => Intl.message(
      "You haven't talked with $userId before. Check it's the right person.",
      args: [userId],
      name: "directInviteFirstContact",
      desc:
          "Dialog for inviting someone to a room: warning when inviting someone you've never talked with; userId is their Matrix ID");

  /// Whether to offer the "Share earlier messages" tick box: only when the
  /// invite would actually send the room's history.
  static bool offersShareChoice(InviteHistory history) =>
      history == InviteHistory.included;

  /// The line under the status chip, if any.
  static String? noteFor(InviteHistory history) => switch (history) {
        InviteHistory.newMessagesOnly => directInviteNewMessagesOnlyNote,
        InviteHistory.notEncrypted => directInviteNotEncryptedNote,
        _ => null,
      };

  /// Asks, then invites [userId] to [roomId]. Returns false when cancelled.
  static Future<bool> invite(BuildContext context,
      {required Client client,
      required InvitationComponent component,
      required String roomId,
      required String roomName,
      required String userId}) async {
    final history = SpaceInviteDialog.statusOf(client, roomId, userId);
    final firstContact = SpaceInviteDialog.isFirstContact(client, userId);

    final shareHistory = await AdaptiveDialog.show<bool>(context,
        title: directInviteTitle,
        builder: (context) => DirectInviteDialog(
            client: client,
            userId: userId,
            roomName: roomName,
            history: history,
            firstContact: firstContact));
    if (shareHistory == null) return false;

    if (!shareHistory && client is MatrixClient) {
      unawaited(inviteWithoutHistory(client, roomId, userId));
    } else {
      unawaited(component.inviteUserToRoom(userId: userId, roomId: roomId));
    }
    return true;
  }

  /// The plain invite API call: the SDK's Client.inviteUser also sends the
  /// room's history keys, so go around it when they're kept back.
  static Future<void> inviteWithoutHistory(
      MatrixClient client, String roomId, String userId) {
    final mx = client.getMatrixClient();
    return matrix.MatrixApi(
            homeserver: mx.homeserver,
            accessToken: mx.accessToken,
            httpClient: mx.httpClient)
        .inviteUser(roomId, userId);
  }

  @override
  State<DirectInviteDialog> createState() => _DirectInviteDialogState();
}

class _DirectInviteDialogState extends State<DirectInviteDialog> {
  bool shareHistory = true;

  Widget chip(BuildContext context, String text, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
          color: color.withAlpha(36), borderRadius: BorderRadius.circular(10)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(text,
            maxLines: 1,
            softWrap: false,
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: color, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget? statusChip(BuildContext context) {
    final dim = Theme.of(context).colorScheme.onSurfaceVariant;
    return switch (widget.history) {
      InviteHistory.included => chip(
          context,
          DirectInviteDialog.directInviteHistoryIncluded,
          Colors.green.shade500,
          Icons.history),
      InviteHistory.newMessagesOnly => chip(
          context,
          DirectInviteDialog.directInviteNewMessagesOnly,
          Colors.amber.shade600,
          Icons.schedule),
      InviteHistory.notEncrypted => chip(context,
          DirectInviteDialog.directInviteNotEncrypted, dim, Icons.lock_open),
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final dim = Theme.of(context).colorScheme.onSurfaceVariant;
    final small = Theme.of(context).textTheme.bodySmall?.copyWith(color: dim);
    final status = statusChip(context);
    final note = DirectInviteDialog.noteFor(widget.history);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MiniProfileView(client: widget.client, userId: widget.userId),
            const SizedBox(height: 8),
            Text(DirectInviteDialog.directInviteTo(widget.roomName),
                style: small),
            if (status != null) ...[
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerLeft, child: status),
            ],
            if (DirectInviteDialog.offersShareChoice(widget.history)) ...[
              const SizedBox(height: 8),
              CheckboxListTile(
                key: const ValueKey("direct-invite-share-history"),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: shareHistory,
                onChanged: (v) => setState(() => shareHistory = v ?? true),
                title: tiamat.Text.label(
                    DirectInviteDialog.directInviteShareHistory),
                subtitle: Text(
                    DirectInviteDialog.directInviteShareHistoryDescription(
                        widget.userId),
                    style: small),
              ),
            ],
            if (note != null) ...[
              const SizedBox(height: 8),
              Text(note, style: small),
            ],
            if (widget.firstContact) ...[
              const SizedBox(height: 12),
              Container(
                key: const ValueKey("direct-invite-first-contact"),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: Colors.amber.withAlpha(28),
                    border: Border.all(color: Colors.amber.withAlpha(90)),
                    borderRadius: BorderRadius.circular(8)),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline,
                          size: 18, color: Colors.amber.shade600),
                      const SizedBox(width: 8),
                      Expanded(
                          child: tiamat.Text.body(
                              DirectInviteDialog.directInviteFirstContact(
                                  widget.userId))),
                    ]),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              height: 40,
              child: tiamat.Button(
                key: const ValueKey("direct-invite-confirm"),
                text: DirectInviteDialog.directInviteConfirm,
                onTap: () => Navigator.pop(
                    context,
                    DirectInviteDialog.offersShareChoice(widget.history)
                        ? shareHistory
                        : true),
              ),
            ),
            const SizedBox(height: 5),
            tiamat.Button.secondary(
              text: CommonStrings.promptCancel,
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }
}
