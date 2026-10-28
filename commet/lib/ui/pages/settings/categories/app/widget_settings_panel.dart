import 'package:commet/main.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:tiamat/tiamat.dart';

String get widgetSettingsHeader => Intl.message("Widgets",
    desc: "Header of the settings panel about where widgets open",
    name: "widgetSettingsHeader");

String get widgetSettingsTitle => Intl.message("Open widgets in",
    desc: "Title of the setting that picks where widgets open",
    name: "widgetSettingsTitle");

String get widgetSettingsDescription => Intl.message(
    "Call widgets (Jitsi, Element Call) and Drawpile always open in your browser: they need browser features the Vommet window doesn't have. You can change this for one widget from its menu.",
    desc: "Description of the setting that picks where widgets open",
    name: "widgetSettingsDescription");

String get widgetSettingsVommetWindow => Intl.message("Vommet window",
    desc: "Choice: widgets open in Vommet's own window",
    name: "widgetSettingsVommetWindow");

String get widgetSettingsVommetWindowDescription =>
    Intl.message("Opens in its own Vommet window. Works without a browser.",
        desc: "Explains the 'Vommet window' choice for where widgets open",
        name: "widgetSettingsVommetWindowDescription");

String get widgetSettingsBrowser => Intl.message("Your browser",
    desc: "Choice: widgets open in the user's default web browser",
    name: "widgetSettingsBrowser");

String get widgetSettingsBrowserDescription =>
    Intl.message("Opens in your default browser, in a normal tab.",
        desc: "Explains the 'Your browser' choice for where widgets open",
        name: "widgetSettingsBrowserDescription");

/// Vommet: Settings › General › Widgets (Linux): widgets open in Vommet's
/// own window or in the default browser.
class WidgetSettingsPanel extends StatefulWidget {
  const WidgetSettingsPanel({super.key});

  @override
  State<WidgetSettingsPanel> createState() => _WidgetSettingsPanelState();
}

class _WidgetSettingsPanelState extends State<WidgetSettingsPanel> {
  @override
  Widget build(BuildContext context) {
    return Panel(
      header: widgetSettingsHeader,
      mode: TileType.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 8,
          children: [
            tiamat.Text(widgetSettingsTitle),
            tiamat.Text.labelLow(widgetSettingsDescription),
            tiamat.DropdownSelector<bool>(
              color: ColorScheme.of(context).surfaceContainerLow,
              items: const [false, true],
              itemHeight: 60,
              itemBuilder: (inBrowser) => Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  tiamat.Text(inBrowser
                      ? widgetSettingsBrowser
                      : widgetSettingsVommetWindow),
                  tiamat.Text.labelLow(inBrowser
                      ? widgetSettingsBrowserDescription
                      : widgetSettingsVommetWindowDescription),
                ],
              ),
              onItemSelected: (inBrowser) async {
                if (inBrowser == null) return;
                await preferences.widgetsOpenInBrowser.set(inBrowser);
                if (mounted) setState(() {});
              },
              value: preferences.widgetsOpenInBrowser.value,
            ),
          ],
        ),
      ),
    );
  }
}
