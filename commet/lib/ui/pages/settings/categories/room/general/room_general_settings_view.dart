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
      this.defaultLevel,
      this.followsDefault = false});
  final PushRule pushRule;

  /// Called with the chosen level, or null for "Use default (…)".
  final void Function(PushRule? rule)? onPushRuleChanged;

  /// Vommet: the level the account's defaults give this room. When set, a
  /// first choice "Use default (…)" naming it follows the defaults (the room
  /// has no rule of its own), like the page's "Use global preference" rows.
  final PushRule? defaultLevel;

  /// Vommet: the room follows the account's defaults, so "Use default (…)"
  /// is selected rather than [pushRule].
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

  String labelPushRuleUseDefault(String level) => Intl.message(
      "Use default ($level)",
      args: [level],
      desc:
          "A room's notification choice to follow the account's default notification settings; the level is what they give here, such as Mentions & Keywords",
      name: "labelPushRuleUseDefault");

  String _levelName(PushRule rule) => switch (rule) {
        PushRule.notify => labelPushRuleNotifyAll,
        PushRule.mentionsOnly => labelPushRuleMentionsAndKeywords,
        PushRule.dontNotify => labelPushRuleNone,
      };

  String get labelRoomSettingsNotifications => Intl.message("Notifications",
      desc: "Label for the notifications section in room settings",
      name: "labelRoomSettingsNotifications");

  /// The selected choice: null is "Use default (…)".
  PushRule? get _selected =>
      defaultLevel != null && followsDefault ? null : pushRule;

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
              if (defaultLevel case final level?)
                tiamat.RadioButton<PushRule?>(
                  groupValue: _selected,
                  value: null,
                  icon: material.Icons.remove_outlined,
                  text: labelPushRuleUseDefault(_levelName(level)),
                  onChanged: onPushRuleChanged,
                ),
              tiamat.RadioButton<PushRule?>(
                groupValue: _selected,
                value: PushRule.notify,
                icon: material.Icons.notifications_active_outlined,
                text: labelPushRuleNotifyAll,
                onChanged: onPushRuleChanged,
              ),
              tiamat.RadioButton<PushRule?>(
                groupValue: _selected,
                value: PushRule.mentionsOnly,
                icon: material.Icons.notification_important_outlined,
                text: labelPushRuleMentionsAndKeywords,
                onChanged: onPushRuleChanged,
              ),
              tiamat.RadioButton<PushRule?>(
                groupValue: _selected,
                value: PushRule.dontNotify,
                icon: material.Icons.notifications_off_outlined,
                text: labelPushRuleNone,
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
