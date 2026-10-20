import 'package:commet/client/components/invitation/invitation.dart';
import 'package:commet/ui/atoms/room_panel_view.dart';
import 'package:commet/ui/organisms/invitation_view/invite_strings.dart';
import 'package:commet/utils/common_strings.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class InvitationDisplay extends StatefulWidget {
  const InvitationDisplay(this.invitation,
      {super.key, this.acceptInvitation, this.rejectInvitation, this.onTap});
  final Invitation invitation;
  final Future<void> Function(Invitation invite)? acceptInvitation;
  final Future<void> Function(Invitation invite)? rejectInvitation;

  /// Vommet: opens the invite page.
  final void Function(Invitation invite)? onTap;

  @override
  State<InvitationDisplay> createState() => _InvitationDisplayState();
}

class _InvitationDisplayState extends State<InvitationDisplay> {
  String labelInvitationBodyWithSender(String user) => Intl.message(
      "$user invited you to a room",
      desc:
          "Message body for when an invitation was received, and we have a name for the sender",
      args: [user],
      name: "labelInvitationBodyWithSender");

  @override
  Widget build(BuildContext context) {
    return RoomPanelView(
      displayName: widget.invitation.displayName ?? "",
      avatar: widget.invitation.avatar,
      color: widget.invitation.color,
      // Vommet: "@x invited you" / "@x wants to message you".
      body: widget.invitation.senderId != null
          ? (widget.invitation.isDirect
              ? inviteRowWantsToMessage(widget.invitation.senderId!)
              : inviteRowInvitedYou(widget.invitation.senderId!))
          : widget.invitation.roomId,
      onTap: widget.onTap == null
          ? null
          : () => widget.onTap!.call(widget.invitation),
      primaryButtonLabel: CommonStrings.promptAccept,
      onPrimaryButtonPressed: acceptInvitation,
      secondaryButtonLabel: CommonStrings.promptReject,
      onSecondaryButtonPressed: rejectInvitation,
    );
  }

  Future<void> acceptInvitation() async {
    await widget.acceptInvitation?.call(widget.invitation);
  }

  Future<void> rejectInvitation() async {
    await widget.rejectInvitation?.call(widget.invitation);
  }
}
