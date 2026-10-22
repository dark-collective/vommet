// Vommet: Settings › Appearance › Theme › Title bar (Linux): the window title
// bar matches the theme, or is forced light or dark for any theme
// (config/title_bar_brightness.dart, Vommet issue 384). Shows nothing on
// other platforms.
import 'package:commet/config/platform_utils.dart';
import 'package:commet/config/title_bar_brightness.dart';
import 'package:commet/main.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class TitleBarSettings extends StatefulWidget {
  const TitleBarSettings({super.key});

  @override
  State<TitleBarSettings> createState() => _TitleBarSettingsState();
}

class _TitleBarSettingsState extends State<TitleBarSettings> {
  static String get labelTitleBar => Intl.message("Title bar",
      desc: "Title of the setting for the colour of the window's title bar",
      name: "labelTitleBar");

  static String get labelTitleBarDescription => Intl.message(
      "Light or dark window title bar. Works with any theme, custom ones too",
      desc: "Description of the title bar colour setting",
      name: "labelTitleBarDescription");

  static String get labelTitleBarFollowTheme => Intl.message("Match theme",
      desc: "Title bar option: light with a light theme, dark with a dark one",
      name: "labelTitleBarFollowTheme");

  static String get labelTitleBarLight => Intl.message("Light",
      desc: "Title bar option: always light", name: "labelTitleBarLight");

  static String get labelTitleBarDark => Intl.message("Dark",
      desc: "Title bar option: always dark", name: "labelTitleBarDark");

  @override
  Widget build(BuildContext context) {
    if (!PlatformUtils.isLinux) return const SizedBox.shrink();
    var value = preferences.linuxTitleBar.value;
    if (!TitleBarBrightness.options.contains(value)) {
      value = TitleBarBrightness.followTheme;
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                tiamat.Text.labelEmphasised(labelTitleBar),
                tiamat.Text.labelLow(labelTitleBarDescription),
              ],
            ),
          ),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                  value: TitleBarBrightness.followTheme,
                  label: Text(labelTitleBarFollowTheme)),
              ButtonSegment(
                  value: TitleBarBrightness.light,
                  label: Text(labelTitleBarLight)),
              ButtonSegment(
                  value: TitleBarBrightness.dark,
                  label: Text(labelTitleBarDark)),
            ],
            selected: {value},
            onSelectionChanged: (selected) async {
              await preferences.linuxTitleBar.set(selected.first);
              if (mounted) setState(() {});
            },
          ),
        ],
      ),
    );
  }
}
