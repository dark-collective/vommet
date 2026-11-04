// Vommet: pick the timezone shared on your profile, instead of always sharing
// the device's own zone.
import 'dart:math';

import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/utils/timezone_utils.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:timezone/timezone.dart' as tz;
import 'package:commet/utils/clock_format.dart';

class TimezoneOption {
  TimezoneOption(this.id, this.offset, this.abbreviation);

  /// IANA id, e.g. Europe/Berlin.
  final String id;
  final Duration offset;
  final String abbreviation;

  String get city => id.split("/").last.replaceAll("_", " ");

  String get region {
    final parts = id.split("/");
    return parts.length > 1
        ? parts.sublist(0, parts.length - 1).join(" / ").replaceAll("_", " ")
        : "";
  }

  String get offsetLabel => TimezoneOptions.formatOffset(offset);

  late final String _haystack = [
    id.replaceAll("_", " "),
    abbreviation,
    offsetLabel.replaceAll("−", "-"),
    offsetLabel.replaceAll("UTC", "GMT").replaceAll("−", "-"),
  ].join("\n").toLowerCase();

  bool matches(List<String> tokens) => tokens.every(_haystack.contains);
}

class TimezoneOptions {
  /// UTC+2, UTC−4, UTC+5:30, UTC
  static String formatOffset(Duration offset) {
    if (offset == Duration.zero) return "UTC";
    final sign = offset.isNegative ? "−" : "+";
    final mins = offset.inMinutes.abs();
    final h = mins ~/ 60;
    final m = mins % 60;
    return m == 0 ? "UTC$sign$h" : "UTC$sign$h:${m.toString().padLeft(2, "0")}";
  }

  /// Every named zone in the timezone database, as of [now].
  static List<TimezoneOption> all({DateTime? now}) {
    final at = (now ?? DateTime.now()).toUtc().millisecondsSinceEpoch;
    final result = <TimezoneOption>[];
    for (final loc in tz.timeZoneDatabase.locations.values) {
      // Skip the Etc/GMT+N style ids; they read backwards (Etc/GMT+5 is UTC−5).
      if (!loc.name.contains("/") || loc.name.startsWith("Etc/")) continue;
      final zone = loc.timeZone(at);
      result.add(TimezoneOption(
          loc.name, Duration(milliseconds: zone.offset), zone.abbreviation));
    }
    result.sort((a, b) => a.id.compareTo(b.id));
    return result;
  }

  static TimezoneOption? byId(String id, {DateTime? now}) {
    try {
      final loc = tz.getLocation(id);
      final zone =
          loc.timeZone((now ?? DateTime.now()).toUtc().millisecondsSinceEpoch);
      return TimezoneOption(
          loc.name, Duration(milliseconds: zone.offset), zone.abbreviation);
    } catch (_) {
      return null;
    }
  }

  /// Zones matching every word of [query] (city, region, abbreviation or
  /// UTC offset). Cities that start with the query come first.
  static List<TimezoneOption> filter(
      List<TimezoneOption> options, String query) {
    final tokens = query
        .toLowerCase()
        .replaceAll("−", "-")
        .split(RegExp(r"\s+"))
        .where((t) => t.isNotEmpty)
        .toList();
    if (tokens.isEmpty) return options;
    final q = tokens.join(" ");
    final hits = options.where((o) => o.matches(tokens)).toList();
    int rank(TimezoneOption o) {
      final city = o.city.toLowerCase();
      if (city.startsWith(q)) return 0;
      if (city.contains(q)) return 1;
      return 2;
    }

    hits.sort((a, b) {
      final r = rank(a) - rank(b);
      if (r != 0) return r;
      final c = a.city.compareTo(b.city);
      return c != 0 ? c : a.id.compareTo(b.id);
    });
    return hits;
  }
}

class TimezonePicker extends StatefulWidget {
  const TimezonePicker({required this.deviceTimezone, this.current, super.key});

  final String deviceTimezone;
  final String? current;

  static String get labelShareTimezoneTitle =>
      Intl.message("Share your timezone",
          name: "labelShareTimezoneTitle",
          desc: "Title of the dialog for picking the timezone on your profile");

  static String get labelShareTimezoneExplanation => Intl.message(
      "People who open your profile see your local time. This is public.",
      name: "labelShareTimezoneExplanation",
      desc: "Explains what sharing a timezone does");

  static String get labelUseDeviceTimezone =>
      Intl.message("Use this device's timezone",
          name: "labelUseDeviceTimezone",
          desc: "Option to share the timezone the device is set to");

  static String get labelPickTimezone => Intl.message("Or pick one",
      name: "labelPickTimezone",
      desc: "Heading above the searchable list of timezones");

  static String get promptSearchTimezone =>
      Intl.message("Search city, region, or UTC offset",
          name: "promptSearchTimezone",
          desc: "Placeholder of the timezone search box");

  static String get labelNoTimezoneMatch => Intl.message("No timezone matches",
      name: "labelNoTimezoneMatch",
      desc: "Shown when the timezone search finds nothing");

  static String promptShareTimezoneCity(String city) =>
      Intl.message("Share $city",
          name: "promptShareTimezoneCity",
          args: [city],
          desc: "Button that shares the picked timezone, named by its city");

  static String get promptCancel => Intl.message("Cancel",
      name: "promptCancel", desc: "Cancel button of the timezone picker");

  /// Returns the picked IANA id, or null when cancelled.
  static Future<String?> show(BuildContext context,
      {required String deviceTimezone, String? current}) async {
    await TimezoneUtils.instance.init();
    if (!context.mounted) return null;
    return AdaptiveDialog.show<String>(context,
        title: labelShareTimezoneTitle,
        scrollable: false,
        initialHeightMobile: 0.8,
        builder: (context) =>
            TimezonePicker(deviceTimezone: deviceTimezone, current: current));
  }

  @override
  State<TimezonePicker> createState() => _TimezonePickerState();
}

class _TimezonePickerState extends State<TimezonePicker> {
  final TextEditingController search = TextEditingController();
  late final List<TimezoneOption> options = TimezoneOptions.all();
  late List<TimezoneOption> shown = options;
  late final TimezoneOption? device =
      TimezoneOptions.byId(widget.deviceTimezone);
  late String selected = widget.current ?? widget.deviceTimezone;

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  String timeIn(TimezoneOption o) {
    final t = DateTime.now().toUtc().add(o.offset);
    return ClockFormat.time(use24: ClockFormat.use24Of(context)).format(t);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dim = scheme.onSurfaceVariant;
    final pickedOption = selected == widget.deviceTimezone
        ? device
        : TimezoneOptions.byId(selected);
    final listHeight = min(360.0, MediaQuery.of(context).size.height * 0.4);

    return RadioGroup<String>(
      groupValue: selected,
      onChanged: (v) {
        if (v != null) setState(() => selected = v);
      },
      child: SizedBox(
        width: 460,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              tiamat.Text.labelLow(
                  TimezonePicker.labelShareTimezoneExplanation),
              const SizedBox(height: 12),
              Material(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(10),
                clipBehavior: Clip.antiAlias,
                child: RadioListTile<String>(
                  key: const ValueKey("TIMEZONE_PICKER_DEVICE"),
                  value: widget.deviceTimezone,
                  controlAffinity: ListTileControlAffinity.trailing,
                  secondary: Icon(Icons.my_location, color: scheme.primary),
                  title: Text(TimezonePicker.labelUseDeviceTimezone,
                      style: theme.textTheme.bodyLarge
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                      device == null
                          ? widget.deviceTimezone
                          : "${device!.id} · ${timeIn(device!)} (${device!.offsetLabel})",
                      style: theme.textTheme.bodySmall?.copyWith(color: dim)),
                ),
              ),
              const SizedBox(height: 12),
              tiamat.Text.labelLow(TimezonePicker.labelPickTimezone),
              const SizedBox(height: 6),
              TextField(
                key: const ValueKey("TIMEZONE_PICKER_SEARCH"),
                controller: search,
                onChanged: (q) =>
                    setState(() => shown = TimezoneOptions.filter(options, q)),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: scheme.surfaceContainerLowest,
                  hintText: TimezonePicker.promptSearchTimezone,
                  prefixIcon: const Icon(Icons.search, size: 18),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:
                          BorderSide(color: scheme.primary, width: 1.5)),
                ),
              ),
              const SizedBox(height: 6),
              Container(
                height: listHeight,
                decoration: BoxDecoration(
                    color: scheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(10)),
                clipBehavior: Clip.antiAlias,
                child: shown.isEmpty
                    ? Center(
                        child: tiamat.Text.labelLow(
                            TimezonePicker.labelNoTimezoneMatch))
                    : ListView.builder(
                        itemCount: shown.length,
                        itemBuilder: (context, i) => _row(context, shown[i]),
                      ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  tiamat.Button.secondary(
                    text: TimezonePicker.promptCancel,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 8),
                  tiamat.Button(
                    key: const ValueKey("TIMEZONE_PICKER_SHARE"),
                    text: TimezonePicker.promptShareTimezoneCity(
                        pickedOption?.city ?? selected),
                    onTap: () => Navigator.of(context).pop(selected),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(BuildContext context, TimezoneOption o) {
    final theme = Theme.of(context);
    final dim = theme.colorScheme.onSurfaceVariant;
    return RadioListTile<String>(
      value: o.id,
      dense: true,
      title: Text(o.city,
          style:
              theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
      subtitle: Text(o.region.isEmpty ? o.id : "${o.region} · ${o.id}",
          style: theme.textTheme.bodySmall?.copyWith(color: dim)),
      secondary: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(timeIn(o),
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          Text("${o.abbreviation} · ${o.offsetLabel}",
              style: theme.textTheme.bodySmall?.copyWith(color: dim)),
        ],
      ),
    );
  }
}
