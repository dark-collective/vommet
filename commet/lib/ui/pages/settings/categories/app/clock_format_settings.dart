import 'package:commet/main.dart';
import 'package:commet/ui/pages/settings/search/settings_search.dart';
import 'package:commet/utils/clock_format.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:tiamat/tiamat.dart';

/// Vommet: Settings › Appearance › Clock, the 12-hour or 24-hour clock for
/// message times and every other time in the app (Vommet issue 347).
class ClockFormatSettings extends StatefulWidget {
  const ClockFormatSettings({super.key});

  @override
  State<ClockFormatSettings> createState() => _ClockFormatSettingsState();
}

class _ClockFormatSettingsState extends State<ClockFormatSettings> {
  /// 4:05 PM, the time each choice is shown with.
  static final _sample = DateTime(2026, 1, 1, 16, 5);

  String _label(ClockStyle style, bool systemUses24) {
    final use24 = ClockFormat.resolve(style, systemUses24: systemUses24);
    final example = ClockFormat.time(use24: use24).format(_sample);
    return switch (style) {
      ClockStyle.system => clockFormatSettingsSystem(example),
      ClockStyle.twelveHour => clockFormatSettingsTwelveHour(example),
      ClockStyle.twentyFourHour => clockFormatSettingsTwentyFourHour(example),
    };
  }

  @override
  Widget build(BuildContext context) {
    // What the platform says, before ClockFormatScope applied the setting.
    final view = View.of(context);
    final systemUses24 = kIsWeb
        ? ClockFormat.localeUses24()
        : MediaQueryData.fromView(view).alwaysUse24HourFormat;
    return SettingsSearchTarget(
      ids: [preferences.clockFormat.key, clockFormatSettingsHeader],
      child: Panel(
        header: clockFormatSettingsHeader,
        mode: TileType.surfaceContainerLow,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 8,
            children: [
              tiamat.Text(clockFormatSettingsTitle),
              tiamat.Text.labelLow(clockFormatSettingsDescription),
              tiamat.DropdownSelector<ClockStyle>(
                color: ColorScheme.of(context).surfaceContainerLow,
                items: ClockStyle.values,
                itemBuilder: (item) => tiamat.Text(_label(item, systemUses24)),
                onItemSelected: (item) async {
                  if (item == null) return;
                  await preferences.clockFormat.set(item.name);
                  if (mounted) setState(() {});
                },
                value: ClockFormat.current,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String get clockFormatSettingsHeader => Intl.message("Clock",
    name: "clockFormatSettingsHeader",
    desc: "Header of the settings panel that picks the 12- or 24-hour clock");

String get clockFormatSettingsTitle => Intl.message("Time format",
    name: "clockFormatSettingsTitle",
    desc: "Title of the setting that picks the 12-hour or 24-hour clock");

String get clockFormatSettingsDescription =>
    Intl.message("How message times and other times in the app are shown",
        name: "clockFormatSettingsDescription",
        desc: "Description of the 12/24-hour clock setting");

String clockFormatSettingsSystem(String example) => Intl.message(
    "System default ($example)",
    args: [example],
    name: "clockFormatSettingsSystem",
    desc:
        "Clock setting choice that follows the system's 12/24-hour setting; example is a sample time such as 16:05",
    examples: const {"example": "16:05"});

String clockFormatSettingsTwelveHour(String example) => Intl.message(
    "12-hour ($example)",
    args: [example],
    name: "clockFormatSettingsTwelveHour",
    desc:
        "Clock setting choice for the 12-hour clock; example is a sample time such as 4:05 PM",
    examples: const {"example": "4:05 PM"});

String clockFormatSettingsTwentyFourHour(String example) => Intl.message(
    "24-hour ($example)",
    args: [example],
    name: "clockFormatSettingsTwentyFourHour",
    desc:
        "Clock setting choice for the 24-hour clock; example is a sample time such as 16:05",
    examples: const {"example": "16:05"});
