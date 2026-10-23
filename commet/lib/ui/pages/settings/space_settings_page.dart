import 'package:commet/client/client.dart';
import 'package:commet/ui/molecules/space_menu.dart';
import 'package:commet/ui/pages/settings/categories/space/settings_category_space.dart';
import 'package:commet/ui/pages/settings/settings_button.dart';
import 'package:commet/ui/pages/settings/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class SpaceSettingsPage extends StatefulWidget {
  const SpaceSettingsPage({super.key, required this.space});
  final Space space;

  @override
  State<SpaceSettingsPage> createState() => _SpaceSettingsPageState();
}

class _SpaceSettingsPageState extends State<SpaceSettingsPage> {
  String get promptLeaveSpace => Intl.message("Leave Space",
      desc: "Text on a button to leave a space", name: "promptLeaveSpace");

  String promptLeaveSpaceConfirmation(String spaceName) => Intl.message(
      "Are you sure you want to leave $spaceName?",
      desc: "Text for the popup dialog confirming the intent to leave a space",
      args: [spaceName],
      name: "promptLeaveSpaceConfirmation");

  @override
  Widget build(BuildContext context) {
    return SettingsPage(
      settings: [
        SettingsCategorySpace(
          widget.space,
        ),
      ],
      buttons: [
        SettingsButton(
            label: promptLeaveSpace,
            icon: Icons.subdirectory_arrow_left_rounded,
            color: Theme.of(context).colorScheme.error,
            onPress: () => leaveSpace(context)),
      ],
    );
  }

  // Vommet: the same confirmation as Leave Space in the space menu (it can
  // also leave the space's rooms).
  Future<void> leaveSpace(BuildContext context) async {
    await SpaceMenu.leave(context, widget.space, onConfirmed: () {
      if (context.mounted) Navigator.pop(context);
    });
  }
}
