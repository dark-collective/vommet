import 'package:commet/main.dart';
import 'package:commet/utils/tray/app_tray.dart';
import 'package:commet/ui/pages/settings/categories/app/boolean_preference_toggle.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import 'package:tiamat/tiamat.dart';

class WindowSettingsPage extends StatefulWidget {
  const WindowSettingsPage({super.key});

  @override
  State<WindowSettingsPage> createState() => _WindowSettingsPageState();
}

class _WindowSettingsPageState extends State<WindowSettingsPage> {
  String get labelSettingsWindowBehaviourTitle =>
      Intl.message("Window behavior",
          desc: "Header for the window behaviour section of settings",
          name: "labelSettingsWindowBehaviourTitle");

  String get labelSettingsMinimizeOnCloseToggle =>
      Intl.message("Minimize on close",
          desc: "Label for the toggle to turn on and off minimize on close",
          name: "labelSettingsMinimizeOnCloseToggle");

  String get labelSettingsMinimizeOnCloseExplanation => Intl.message(
      "When closing the window, the app will be minimized instead of exited",
      desc: "Explains what the 'minimize on close' setting does",
      name: "labelSettingsMinimizeOnCloseExplanation");

  String get labelSettingsShowTrayIconToggle => Intl.message("Show tray icon",
      desc: "Label for the toggle that shows the app's icon in the system tray",
      name: "labelSettingsShowTrayIconToggle");

  String get labelSettingsShowTrayIconExplanation => Intl.message(
      "Keep an icon in the system tray to show or hide the window and to quit. Needs a desktop or panel with a tray",
      desc: "Explains what the 'show tray icon' setting does",
      name: "labelSettingsShowTrayIconExplanation");

  String get labelSettingsCloseToTrayToggle => Intl.message("Close to tray",
      desc:
          "Label for the toggle that makes closing the window hide it to the tray",
      name: "labelSettingsCloseToTrayToggle");

  String get labelSettingsCloseToTrayExplanation => Intl.message(
      "When closing the window, hide it and keep the app running in the tray. Without a tray, closing works as usual",
      desc: "Explains what the 'close to tray' setting does",
      name: "labelSettingsCloseToTrayExplanation");

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Panel(
      header: labelSettingsWindowBehaviourTitle,
      mode: TileType.surfaceContainerLow,
      child: Column(children: [
        BooleanPreferenceToggle(
          preference: preferences.minimizeOnClose,
          title: labelSettingsMinimizeOnCloseToggle,
          description: labelSettingsMinimizeOnCloseExplanation,
        ),
        if (AppTray.isSupported)
          BooleanPreferenceToggle(
            preference: preferences.showTrayIcon,
            title: labelSettingsShowTrayIconToggle,
            description: labelSettingsShowTrayIconExplanation,
          ),
        if (AppTray.isSupported)
          BooleanPreferenceToggle(
            preference: preferences.closeToTray,
            title: labelSettingsCloseToTrayToggle,
            description: labelSettingsCloseToTrayExplanation,
          ),
      ]),
    );
  }
}
