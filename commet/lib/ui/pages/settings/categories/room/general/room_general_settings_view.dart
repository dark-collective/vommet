import 'package:commet/client/client.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:flutter/material.dart' as material;

class RoomGeneralSettingsView extends StatelessWidget {
  const RoomGeneralSettingsView(
      {super.key,
      required this.pushRule,
      this.onPushRuleChanged,
      this.note,
      this.followsDefault = false});
  final PushRule pushRule;
  final void Function(PushRule? rule)? onPushRuleChanged;

  /// Vommet: [pushRule] comes from the account's defaults (the room has no
  /// rule of its own), so its choice reads "Default (…)".
  final bool followsDefault;

  /// Optional line under the choices saying what they actually affect.
  final String? note;

  String get labelPushRuleNotifyAll => Intl.message("All Messages",
      desc: "Label for the push rule which notifies for all received messages",
      name: "labelPushRuleNotifyAll");

  String get labelPushRuleMentionsAndKeywords => Intl.message(
      "Mentions & Keywords",
      desc:
          "Label for the push rule which notifies only for keywords and mentions",
      name: "labelPushRuleMentionsAndKeywords");

  String get labelPushRuleNone => Intl.message("Mute",
      desc: "Label for the push rule which sends no notifications",
      name: "labelPushRuleNone");

  String labelPushRuleDefault(String level) => Intl.message("Default ($level)",
      args: [level],
      desc:
          "A room's notification choice when the room follows the account's default notification settings; the level is what they give here, such as Mentions & Keywords",
      name: "labelPushRuleDefault");

  String _label(PushRule rule, String label) =>
      followsDefault && rule == pushRule ? labelPushRuleDefault(label) : label;

  String get labelRoomSettingsNotifications => Intl.message("Notifications",
      desc: "Label for the notifications section in room settings",
      name: "labelRoomSettingsNotifications");

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [notificationSettings()],
    );
  }

  Widget notificationSettings() {
    return tiamat.Panel(
        mode: tiamat.TileType.surfaceContainerLow,
        header: labelRoomSettingsNotifications,
        child: material.Material(
          color: material.Colors.transparent,
          child: Column(
            children: [
              tiamat.RadioButton<PushRule>(
                groupValue: pushRule,
                value: PushRule.notify,
                icon: material.Icons.notifications_active_outlined,
                text: _label(PushRule.notify, labelPushRuleNotifyAll),
                onChanged: onPushRuleChanged,
              ),
              tiamat.RadioButton<PushRule>(
                groupValue: pushRule,
                value: PushRule.mentionsOnly,
                icon: material.Icons.notification_important_outlined,
                text: _label(
                    PushRule.mentionsOnly, labelPushRuleMentionsAndKeywords),
                onChanged: onPushRuleChanged,
              ),
              tiamat.RadioButton<PushRule>(
                groupValue: pushRule,
                value: PushRule.dontNotify,
                icon: material.Icons.notifications_off_outlined,
                text: _label(PushRule.dontNotify, labelPushRuleNone),
                onChanged: onPushRuleChanged,
              ),
              if (note != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: tiamat.Text.labelLow(note!),
                  ),
                ),
            ],
          ),
        ));
  }
}
