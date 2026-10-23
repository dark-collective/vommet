import 'package:commet/ui/atoms/space_list.dart';
import 'package:commet/ui/molecules/composer_notice.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/utils/common_strings.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';

import '../../client/client.dart';

class SpaceViewer extends StatefulWidget {
  const SpaceViewer(
    this.space, {
    super.key,
    this.onRoomSelected,
  });
  final Space space;
  final void Function(Room, {bool bypassSpecialRoomType})? onRoomSelected;

  @override
  State<SpaceViewer> createState() => _SpaceViewerState();
}

class _SpaceViewerState extends State<SpaceViewer> {
  @override
  Widget build(BuildContext context) {
    final list = Padding(
        padding: const EdgeInsets.all(8.0),
        child: SpaceList(
          widget.space,
          onRoomSelected: widget.onRoomSelected,
        ));

    return Material(
      color: Colors.transparent,
      // Vommet: a banned space shows its notice above the rooms you're
      // still in (a space ban doesn't ban you from its rooms)
      child: StreamBuilder(
          stream: widget.space.onUpdate,
          builder: (context, _) {
            if (!widget.space.isBanned) return list;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [bannedNotice(context), list],
            );
          }),
    );
  }

  String get bannedFromSpaceNotice =>
      Intl.message("You were banned from this space.",
          name: "bannedFromSpaceNotice",
          desc: "Shown at the top of a space the user was banned from");

  String bannedFromSpaceReason(String reason) => Intl.message("Reason: $reason",
      args: [reason],
      name: "bannedFromSpaceReason",
      desc: "The reason a moderator gave for banning the user from a space");

  String get dismissBannedSpace => Intl.message("Dismiss",
      name: "dismissBannedSpace",
      desc: "Button that removes a space the user was banned from");

  String dismissBannedSpacePrompt(String space) => Intl.message(
      "Remove $space from your list? You stay in its rooms.",
      args: [space],
      name: "dismissBannedSpacePrompt",
      desc: "Confirmation before forgetting a space the user was banned from");

  Widget bannedNotice(BuildContext context) {
    final reason = widget.space.banReason;
    return ComposerNotice(
      icon: Icons.block,
      title: bannedFromSpaceNotice,
      subtitle: reason == null ? null : bannedFromSpaceReason(reason),
      actionLabel: dismissBannedSpace,
      destructiveAction: true,
      onAction: () async {
        final confirmed = await AdaptiveDialog.confirmation(context,
            prompt: dismissBannedSpacePrompt(widget.space.displayName),
            confirmationText: dismissBannedSpace,
            cancelText: CommonStrings.promptCancel,
            dangerous: true);
        if (confirmed == true) await widget.space.dismissBan();
      },
    );
  }
}
