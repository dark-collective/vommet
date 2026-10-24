import 'package:commet/ui/molecules/pinned_message_bar.dart';
import 'package:commet/ui/pages/settings/categories/app/boolean_preference_toggle.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart';

/// Vommet: the pinned message bar's toggles, in Settings › Appearance ›
/// Other Options.
class PinnedBarSettings extends StatelessWidget {
  const PinnedBarSettings({super.key});

  String get pinnedBarSettingsShowBar => Intl.message(
      "Show pinned messages bar",
      name: "pinnedBarSettingsShowBar",
      desc: "Label for the setting that shows a bar of pinned messages above "
          "the chat");

  String get pinnedBarSettingsShowBarDescription => Intl.message(
      "Show the room's pinned messages above the chat. Tap the bar to jump "
      "to one; each tap moves on to the next.",
      name: "pinnedBarSettingsShowBarDescription",
      desc: "Description for the setting that shows the pinned message bar");

  String get pinnedBarSettingsPersonal =>
      Intl.message("Include messages pinned for you",
          name: "pinnedBarSettingsPersonal",
          desc: "Label for the setting that adds your personal pins to the "
              "pinned message bar");

  String get pinnedBarSettingsPersonalDescription => Intl.message(
      "Messages you pinned only for yourself join the bar, marked "
      "“Pinned for you”.",
      name: "pinnedBarSettingsPersonalDescription",
      desc: "Description for the setting that adds your personal pins to the "
          "pinned message bar");

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        BooleanPreferenceToggle(
          preference: PinnedMessageBar.showBar,
          title: pinnedBarSettingsShowBar,
          description: pinnedBarSettingsShowBarDescription,
        ),
        const Seperator(),
        BooleanPreferenceToggle(
          preference: PinnedMessageBar.includePersonal,
          title: pinnedBarSettingsPersonal,
          description: pinnedBarSettingsPersonalDescription,
        ),
      ],
    );
  }
}
