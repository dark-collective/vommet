import 'package:commet/ui/pages/settings/app_settings_page.dart';
import 'package:commet/utils/window_management.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' show CircleButton;

/// Quit button opposite the back button of the app settings (Vommet issue
/// 348). It quits even with "Minimize on close" on, which otherwise leaves
/// no way to exit. Shown only in the app settings on Linux and Windows, so
/// room and space settings, which share the same pages, don't get it.
class SettingsQuitButton extends StatelessWidget {
  const SettingsQuitButton({this.show, this.quit, super.key});

  /// Replaces the check for the app settings on Linux or Windows (tests).
  final bool? show;

  /// Replaces [WindowManagement.quit] (tests).
  final Future<void> Function()? quit;

  static const ValueKey buttonKey = ValueKey("SETTINGS_QUIT_BUTTON");

  static String get promptQuitApp => Intl.message("Quit",
      name: "promptQuitApp",
      desc:
          "Tooltip of the power button at the top of the app settings on desktop, which exits the app completely, even when 'Minimize on close' is on");

  @override
  Widget build(BuildContext context) {
    final shown = show ??
        (WindowManagement.isSupported &&
            context.findAncestorWidgetOfExactType<AppSettingsPage>() != null);
    if (!shown) return const SizedBox.shrink();

    return Tooltip(
      message: promptQuitApp,
      child: CircleButton(
        key: buttonKey,
        radius: 25,
        icon: Icons.power_settings_new,
        onPressed: quit ?? WindowManagement.quit,
      ),
    );
  }
}
