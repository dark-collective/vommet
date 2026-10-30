import 'package:commet/ui/pages/settings/mobile_settings_page.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet: the red Leave button at the bottom of a room's or space's General
/// settings (Element has it there too; the settings sidebar keeps its own).
class SettingsLeaveButton extends StatelessWidget {
  const SettingsLeaveButton({required this.label, this.onTap, super.key});

  final String label;
  final void Function()? onTap;

  /// Closes the settings the button sits in. On mobile a tab is its own
  /// route on top of the settings list, so that one goes too.
  static void closeSettings(BuildContext context) {
    final navigator = Navigator.of(context);
    final inSubPage =
        context.findAncestorWidgetOfExactType<SettingsSubPage>() != null;
    navigator.pop();
    if (inSubPage && navigator.canPop()) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        height: 40,
        width: 220,
        child: tiamat.Button.danger(text: label, onTap: onTap),
      ),
    );
  }
}
