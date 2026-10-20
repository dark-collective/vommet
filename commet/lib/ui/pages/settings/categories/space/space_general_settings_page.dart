import 'package:commet/client/client.dart';
import 'package:commet/client/matrix/matrix_space.dart';
import 'package:commet/ui/pages/matrix/room_address_settings/matrix_room_address_settings.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/nicknames/matrix_nicknames.dart';
import 'package:commet/ui/pages/settings/categories/room/general/nickname_settings.dart';
import 'package:flutter/widgets.dart';
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
        ]
      ],
    );
  }

  void setPushRule(PushRule? rule) {
    if (rule == null) return;

    setState(() {
      pushRule = rule;
    });

    widget.space.setPushRule(rule);
  }
}
