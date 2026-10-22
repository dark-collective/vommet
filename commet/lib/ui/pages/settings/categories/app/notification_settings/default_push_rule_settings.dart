import 'package:commet/client/matrix/matrix_default_push_rule.dart';
import 'package:commet/client/room.dart';
import 'package:commet/config/preferences/string_preference.dart';
import 'package:commet/main.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet: picks the notification level applied to rooms and direct chats
/// when you join them.
class DefaultPushRuleSettings extends StatefulWidget {
  const DefaultPushRuleSettings({super.key});

  @override
  State<DefaultPushRuleSettings> createState() =>
      _DefaultPushRuleSettingsState();
}

class _DefaultPushRuleSettingsState extends State<DefaultPushRuleSettings> {
  String get labelDefaultPushRuleRooms => Intl.message("Rooms you join",
      desc: "Title of the setting for the default notification level of "
          "newly joined group rooms",
      name: "labelDefaultPushRuleRooms");

  String get labelDefaultPushRuleRoomsDescription =>
      Intl.message("Notification level given to a room when you join it",
          desc: "Description of the setting for the default notification level "
              "of newly joined group rooms",
          name: "labelDefaultPushRuleRoomsDescription");

  String get labelDefaultPushRuleDirect => Intl.message("Direct messages",
      desc: "Title of the setting for the default notification level of "
          "newly joined direct chats",
      name: "labelDefaultPushRuleDirect");

  String get labelDefaultPushRuleDirectDescription => Intl.message(
      "Notification level given to a direct chat when you accept it",
      desc: "Description of the setting for the default notification level "
          "of newly joined direct chats",
      name: "labelDefaultPushRuleDirectDescription");

  String get labelDefaultPushRuleNote => Intl.message(
      "Rooms you're already in keep their level, and you can still change any room in its own settings. Account default leaves new rooms following the defaults above.",
      desc: "Note under the default notification level settings",
      name: "labelDefaultPushRuleNote");

  String get labelDefaultPushRuleAccount => Intl.message("Account default",
      desc: "Default notification level option: leave new rooms following "
          "the account's default notifications",
      name: "labelDefaultPushRuleAccount");

  String get labelDefaultPushRuleNotifyAll => Intl.message("All Messages",
      desc: "Default notification level option: notify for every message",
      name: "labelDefaultPushRuleNotifyAll");

  String get labelDefaultPushRuleMentions => Intl.message("Mentions & Keywords",
      desc: "Default notification level option: notify only for mentions and "
          "keywords",
      name: "labelDefaultPushRuleMentions");

  String get labelDefaultPushRuleMute => Intl.message("Mute",
      desc: "Default notification level option: no notifications",
      name: "labelDefaultPushRuleMute");

  static final List<String> options = [
    MatrixDefaultPushRule.accountDefault,
    for (final rule in PushRule.values) rule.name,
  ];

  String label(String option) {
    switch (MatrixDefaultPushRule.parse(option)) {
      case null:
        return labelDefaultPushRuleAccount;
      case PushRule.notify:
        return labelDefaultPushRuleNotifyAll;
      case PushRule.mentionsOnly:
        return labelDefaultPushRuleMentions;
      case PushRule.dontNotify:
        return labelDefaultPushRuleMute;
    }
  }

  IconData icon(String option) {
    switch (MatrixDefaultPushRule.parse(option)) {
      case null:
        return Icons.notifications_none_outlined;
      case PushRule.notify:
        return Icons.notifications_active_outlined;
      case PushRule.mentionsOnly:
        return Icons.notification_important_outlined;
      case PushRule.dontNotify:
        return Icons.notifications_off_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        picker(preferences.defaultRoomPushRule, labelDefaultPushRuleRooms,
            labelDefaultPushRuleRoomsDescription),
        const SizedBox(height: 8),
        picker(preferences.defaultDirectPushRule, labelDefaultPushRuleDirect,
            labelDefaultPushRuleDirectDescription),
        const SizedBox(height: 8),
        tiamat.Text.labelLow(labelDefaultPushRuleNote),
      ],
    );
  }

  Widget picker(StringPreference preference, String title, String description) {
    final value = options.contains(preference.value)
        ? preference.value
        : MatrixDefaultPushRule.accountDefault;

    return Container(
      decoration: BoxDecoration(
          color: ColorScheme.of(context).surfaceContainer.withAlpha(100),
          border: BoxBorder.all(
              color: ColorScheme.of(context).secondary.withAlpha(20)),
          borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            tiamat.Text(title),
            tiamat.Text.labelLow(description),
            const SizedBox(height: 8),
            tiamat.DropdownSelector<String>(
                color: ColorScheme.of(context).surfaceContainerLow,
                items: options,
                itemBuilder: (item) => Row(
                      children: [
                        Icon(icon(item), size: 18),
                        const SizedBox(width: 8),
                        tiamat.Text(label(item)),
                      ],
                    ),
                onItemSelected: (item) async {
                  if (item == null) return;
                  await preference.set(item);
                  if (mounted) setState(() {});
                },
                value: value),
          ],
        ),
      ),
    );
  }
}
