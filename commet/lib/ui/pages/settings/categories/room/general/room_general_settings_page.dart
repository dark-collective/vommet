import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/client/room.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/pages/settings/categories/room/general/room_general_chat_privacy.dart';
import 'package:commet/ui/pages/matrix/room_address_settings/matrix_room_address_settings.dart';
import 'package:commet/ui/pages/settings/categories/room/general/room_general_settings_view.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/nicknames/matrix_nicknames.dart';
import 'package:commet/ui/pages/settings/categories/room/general/nickname_settings.dart';
import 'package:commet/ui/pages/settings/categories/room/general/room_general_url_previews.dart';
import 'package:commet/ui/pages/settings/categories/room/general/settings_leave_button.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class RoomGeneralSettingsPage extends StatefulWidget {
  const RoomGeneralSettingsPage({super.key, required this.room});
  final Room room;
  @override
  State<RoomGeneralSettingsPage> createState() =>
      _RoomGeneralSettingsPageState();
}

class _RoomGeneralSettingsPageState extends State<RoomGeneralSettingsPage> {
  late PushRule pushRule;

  String get promptLeaveRoomFromGeneral => Intl.message("Leave room",
      name: "promptLeaveRoomFromGeneral",
      desc: "Button at the bottom of a room's General settings to leave it");

  String promptLeaveRoomFromGeneralConfirmation(String roomName) =>
      Intl.message("Are you sure you want to leave $roomName?",
          args: [roomName],
          name: "promptLeaveRoomFromGeneralConfirmation",
          desc: "Confirmation before leaving a room from its General settings");

  @override
  void initState() {
    pushRule = widget.room.pushRule;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        RoomGeneralSettingsView(
          pushRule: pushRule,
          onPushRuleChanged: setPushRule,
        ),
        const SizedBox(
          height: 10,
        ),
        RoomGeneralChatPrivacySettings(widget.room),
        if (widget.room is MatrixRoom) ...[
          const SizedBox(
            height: 10,
          ),
          MatrixRoomAddressSettings((widget.room as MatrixRoom).matrixRoom),
          const SizedBox(
            height: 10,
          ),
          MatrixRoomUrlPreviewSettings((widget.room as MatrixRoom).matrixRoom),
        ],
        if (widget.room.client is MatrixClient && MatrixNicknames.enabled) ...[
          const SizedBox(height: 10),
          NicknameSettings(
              client: widget.room.client as MatrixClient,
              roomId: widget.room.identifier),
        ],
        const SizedBox(
          height: 20,
        ),
        SettingsLeaveButton(
          label: promptLeaveRoomFromGeneral,
          onTap: () => leaveRoom(context),
        ),
      ],
    );
  }

  // The same confirmation as the settings sidebar's Leave Room button.
  Future<void> leaveRoom(BuildContext context) async {
    if (await AdaptiveDialog.confirmation(context,
            title: promptLeaveRoomFromGeneral,
            prompt:
                promptLeaveRoomFromGeneralConfirmation(widget.room.displayName),
            dangerous: true) !=
        true) {
      return;
    }
    if (context.mounted) SettingsLeaveButton.closeSettings(context);
    await widget.room.client.leaveRoom(widget.room);
  }

  void setPushRule(PushRule? rule) {
    if (rule == null) return;

    setState(() {
      pushRule = rule;
    });

    widget.room.setPushRule(rule);
  }
}
