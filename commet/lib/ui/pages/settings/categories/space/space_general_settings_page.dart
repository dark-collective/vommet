import 'package:commet/client/client.dart';
import 'package:commet/client/matrix/matrix_space.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/organisms/notification_level/apply_push_rule.dart';
import 'package:commet/ui/pages/matrix/room_address_settings/matrix_room_address_settings.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/nicknames/matrix_nicknames.dart';
import 'package:commet/ui/pages/settings/categories/room/general/nickname_settings.dart';
import 'package:commet/ui/pages/settings/categories/room/general/settings_leave_button.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../room/general/room_general_settings_view.dart';

class SpaceGeneralSettingsPage extends StatefulWidget {
  const SpaceGeneralSettingsPage({super.key, required this.space});
  final Space space;

  @override
  State<SpaceGeneralSettingsPage> createState() =>
      _SpaceGeneralSettingsPageState();
}

class _SpaceGeneralSettingsPageState extends State<SpaceGeneralSettingsPage> {
  late PushRule pushRule;

  // Vommet issue 315: says what the choice does. Since issue 631 it is also
  // offered for the space's rooms and followed by rooms joined in it later;
  // Mute also hides the space's unread dot.
  String get labelSpaceNotificationsNote => Intl.message(
      "Choosing a level offers to set it on the space's rooms (muted rooms and direct messages keep theirs), and rooms you join in the space later follow it. Mute also hides the space's unread dot. You can still change any room in its own settings.",
      desc: "Note under a space's notification choices: what they change",
      name: "labelSpaceNotificationsNote");

  String get promptLeaveSpaceFromGeneral => Intl.message("Leave space",
      name: "promptLeaveSpaceFromGeneral",
      desc: "Button at the bottom of a space's General settings to leave it");

  String promptLeaveSpaceFromGeneralConfirmation(String spaceName) =>
      Intl.message("Are you sure you want to leave $spaceName?",
          args: [spaceName],
          name: "promptLeaveSpaceFromGeneralConfirmation",
          desc:
              "Confirmation before leaving a space from its General settings");

  @override
  void initState() {
    pushRule = widget.space.pushRule;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        RoomGeneralSettingsView(
          pushRule: pushRule,
          onPushRuleChanged: setPushRule,
          note: labelSpaceNotificationsNote,
        ),
        const SizedBox(
          height: 10,
        ),
        if (widget.space is MatrixSpace)
          MatrixRoomAddressSettings((widget.space as MatrixSpace).matrixRoom),
        if (widget.space.client is MatrixClient && MatrixNicknames.enabled) ...[
          const SizedBox(height: 10),
          NicknameSettings(
              client: widget.space.client as MatrixClient,
              roomId: widget.space.identifier,
              space: widget.space),
        ],
        const SizedBox(
          height: 20,
        ),
        SettingsLeaveButton(
          label: promptLeaveSpaceFromGeneral,
          onTap: () => leaveSpace(context),
        ),
      ],
    );
  }

  // The same confirmation as the settings sidebar's Leave Space button.
  Future<void> leaveSpace(BuildContext context) async {
    if (await AdaptiveDialog.confirmation(context,
            title: promptLeaveSpaceFromGeneral,
            prompt: promptLeaveSpaceFromGeneralConfirmation(
                widget.space.displayName),
            dangerous: true) !=
        true) {
      return;
    }
    if (context.mounted) SettingsLeaveButton.closeSettings(context);
    await widget.space.client.leaveSpace(widget.space);
  }

  void setPushRule(PushRule? rule) {
    if (rule == null) return;

    setState(() {
      pushRule = rule;
    });

    // Vommet issue 631: Discord-style, the space's level is offered for its
    // rooms too, and rooms joined in it later follow it.
    widget.space.setPushRule(rule).then((_) {
      if (!mounted) return;
      ApplyPushRule.confirmAndApply(context,
          target: rule,
          taskName: widget.space.displayName,
          sources: [(widget.space.client, widget.space.roomsWithChildren)]);
    });
  }
}
