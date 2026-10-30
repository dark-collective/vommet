import 'package:commet/config/build_config.dart';
import 'package:commet/ui/pages/settings/settings_button.dart';
import 'package:commet/utils/window_management.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// "Quit Vommet" at the bottom of the app settings list (Vommet issue 348),
/// where Discord puts Log Out. It quits even with "Minimize on close" on,
/// which otherwise leaves no way to exit. Only AppSettingsPage passes it, so
/// room and space settings, which share the same pages, don't get it; and
/// only on Linux and Windows, where the app manages its own window.
class SettingsQuitButton {
  static const ValueKey buttonKey = ValueKey("SETTINGS_QUIT_BUTTON");

  static String promptQuitApp(String app) => Intl.message("Quit $app",
      args: [app],
      name: "promptQuitApp",
      desc:
          "Entry at the bottom of the app settings list on desktop that exits the app completely, even when 'Minimize on close' is on",
      examples: const {"app": "Vommet"});

  /// The settings list's bottom entries: Quit, or none where the app can't
  /// quit itself. [supported] replaces the platform check and [quit]
  /// replaces [WindowManagement.quit] (tests).
  static List<SettingsButton>? buttons(
      {bool? supported, Future<void> Function()? quit}) {
    if (!(supported ?? WindowManagement.isSupported)) return null;
    return [
      SettingsButton(
        key: buttonKey,
        label: promptQuitApp(BuildConfig.app),
        icon: Icons.power_settings_new,
        onPress: quit ?? WindowManagement.quit,
      ),
    ];
  }
}
