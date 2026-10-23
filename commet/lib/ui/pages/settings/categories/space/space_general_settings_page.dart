import 'package:commet/client/client.dart';
import 'package:commet/client/matrix/matrix_space.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
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

  // Vommet issue 315: the choice only changes the space's own (empty) room.
  // Vommet reads Mute as "hide this space's unread dot"; each room keeps its
  // own notification setting.
  String get labelSpaceNotificationsNote => Intl.message(
      "Mute hides this space's unread dot. Notifications for its rooms are set in each room.",
      desc:
          "Note under a space's notification choices: they don't change the rooms in the space",
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

    widget.space.setPushRule(rule);
  }
}
