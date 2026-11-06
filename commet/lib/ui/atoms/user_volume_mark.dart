import 'dart:async';

import 'package:commet/main.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Vommet issue 1078: how a saved call volume compares to 100%.
enum VolumeMarkState { none, louder, quieter, muted }

/// Vommet issue 1078: how [UserVolumeMark] shows a changed volume
/// (Settings › Voice, [Preferences.voipVolumeMarkStyle]).
enum VolumeMarkStyle {
  icon,
  percent,
  both;

  static VolumeMarkStyle parse(String value) => VolumeMarkStyle.values
      .firstWhere((s) => s.name == value, orElse: () => VolumeMarkStyle.icon);
}

/// Vommet issue 1078: a small speaker mark next to someone whose call
/// volume you changed (louder, quieter or muted), with "You set <name> to
/// <n>%" as its tooltip. Shows nothing at 100%. Follows volume changes and
/// the display setting live.
class UserVolumeMark extends StatefulWidget {
  const UserVolumeMark(
      {required this.volumeKey,
      required this.name,
      this.size = 14,
      this.padding = const EdgeInsets.only(left: 4),
      this.mutedColor,
      this.color,
      super.key});

  /// The key the volume is saved under ([Preferences.getVoipUserVolume]):
  /// the user id, or "stream:<user id>" for their screen share's sound.
  final String volumeKey;

  final String name;

  final double size;

  /// Around the mark, only while it shows.
  final EdgeInsets padding;

  /// The color of louder and quieter (default: onSurfaceVariant).
  final Color? color;

  /// The color of muted (default: the theme's error color).
  final Color? mutedColor;

  static String userVolumeMarkTooltip(String name, int percent) => Intl.message(
      "You set $name to $percent%",
      name: "userVolumeMarkTooltip",
      args: [name, percent],
      desc:
          "Tooltip and screen reader label of the small speaker next to someone whose call volume you changed");

  static String get labelVoipVolumeMarkStyle => Intl.message(
      "Show changed volumes as",
      name: "labelVoipVolumeMarkStyle",
      desc:
          "Voice settings: title of the choice of how a person's changed call volume shows next to them");

  static String get labelVoipVolumeMarkStyleDescription => Intl.message(
      "A mark next to people whose call volume you changed, in calls and under voice rooms",
      name: "labelVoipVolumeMarkStyleDescription",
      desc: "Voice settings: description of 'Show changed volumes as'");

  static String get labelVoipVolumeMarkIcon => Intl.message("Icon",
      name: "labelVoipVolumeMarkIcon",
      desc: "Voice settings, 'Show changed volumes as': a speaker icon");

  static String get labelVoipVolumeMarkPercent => Intl.message("Percentage",
      name: "labelVoipVolumeMarkPercent",
      desc: "Voice settings, 'Show changed volumes as': the volume, e.g. 150%");

  static String get labelVoipVolumeMarkBoth => Intl.message(
      "Icon and percentage",
      name: "labelVoipVolumeMarkBoth",
      desc:
          "Voice settings, 'Show changed volumes as': the icon and the volume");

  static String styleLabel(String style) =>
      switch (VolumeMarkStyle.parse(style)) {
        VolumeMarkStyle.icon => labelVoipVolumeMarkIcon,
        VolumeMarkStyle.percent => labelVoipVolumeMarkPercent,
        VolumeMarkStyle.both => labelVoipVolumeMarkBoth,
      };

  /// Follows the shown percentage, so the icon and the text agree: within
  /// 0.005 of 1.0 counts as 100%, below 0.005 as muted.
  static VolumeMarkState stateFor(double volume) {
    final percent = percentOf(volume);
    if (percent <= 0) return VolumeMarkState.muted;
    if (percent == 100) return VolumeMarkState.none;
    return percent > 100 ? VolumeMarkState.louder : VolumeMarkState.quieter;
  }

  static int percentOf(double volume) => (volume * 100).round();

  @override
  State<UserVolumeMark> createState() => _UserVolumeMarkState();
}

class _UserVolumeMarkState extends State<UserVolumeMark> {
  StreamSubscription? volumeSub;
  StreamSubscription? settingSub;

  @override
  void initState() {
    super.initState();
    volumeSub = preferences.onVoipUserVolumeChanged.listen((key) {
      if (key == widget.volumeKey && mounted) setState(() {});
    });
    settingSub = preferences.onSettingChanged.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    volumeSub?.cancel();
    settingSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final volume = preferences.getVoipUserVolume(widget.volumeKey);
    final state = UserVolumeMark.stateFor(volume);
    if (state == VolumeMarkState.none) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final color = state == VolumeMarkState.muted
        ? widget.mutedColor ?? scheme.error
        : widget.color ?? scheme.onSurfaceVariant;
    final percent = UserVolumeMark.percentOf(volume);
    final style = VolumeMarkStyle.parse(preferences.voipVolumeMarkStyle.value);
    final label = UserVolumeMark.userVolumeMarkTooltip(widget.name, percent);
    final icon = switch (state) {
      VolumeMarkState.louder => Icons.volume_up_rounded,
      VolumeMarkState.quieter => Icons.volume_down_rounded,
      _ => Icons.volume_off_rounded,
    };
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        excludeSemantics: true,
        child: Padding(
          padding: widget.padding,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (style != VolumeMarkStyle.percent)
              Icon(icon, size: widget.size, color: color),
            if (style != VolumeMarkStyle.icon)
              Text("$percent%",
                  style: TextStyle(
                      fontSize: widget.size * 0.8,
                      fontWeight: FontWeight.w600,
                      color: color)),
          ]),
        ),
      ),
    );
  }
}
