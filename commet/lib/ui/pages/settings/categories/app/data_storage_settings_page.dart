import 'dart:math' as math;

import 'package:commet/cache/file_cache.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/navigation/navigation_utils.dart';
import 'package:commet/ui/pages/settings/categories/app/auto_download_settings.dart';
import 'package:commet/ui/pages/settings/mobile_settings_page.dart';
import 'package:commet/utils/media_auto_download.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Vommet: Settings › Data and storage (Vommet issue 75). Shows how much the
/// media cache uses and opens [StorageUsagePage].
class DataStorageSettingsPage extends StatefulWidget {
  const DataStorageSettingsPage({super.key});

  @override
  State<DataStorageSettingsPage> createState() =>
      _DataStorageSettingsPageState();
}

class _DataStorageSettingsPageState extends State<DataStorageSettingsPage> {
  String get labelDiskUsage => Intl.message("Disk usage",
      desc: "Header for the disk usage section in data and storage settings",
      name: "labelDiskUsage");

  String get labelStorageUsage => Intl.message("Storage usage",
      desc: "Opens the page showing what the media cache uses",
      name: "labelStorageUsage");

  int? cacheBytes;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    final usage = await fileCache?.usage();
    if (!mounted || usage == null) return;
    setState(
        () => cacheBytes = usage.values.fold<int>(0, (a, e) => a + e.bytes));
  }

  Future<void> openStorageUsage() async {
    await NavigationUtils.navigateTo(
        context, SettingsSubPage(builder: (_) => const StorageUsagePage()));
    refresh();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SettingsCard(
          title: labelDiskUsage,
          children: [
            InkWell(
              mouseCursor: WidgetStateMouseCursor.clickable,
              onTap: openStorageUsage,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 12, 12),
                child: Row(children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        borderRadius: BorderRadius.circular(10)),
                    child: Icon(Icons.donut_large,
                        color: theme.colorScheme.onPrimary, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(labelStorageUsage,
                        style: theme.textTheme.bodyLarge
                            ?.copyWith(color: theme.colorScheme.onSurface)),
                  ),
                  if (cacheBytes != null)
                    Text(FileCache.formatSize(cacheBytes!),
                        style: theme.textTheme.bodyLarge
                            ?.copyWith(color: theme.colorScheme.primary)),
                  Icon(Icons.chevron_right,
                      color: theme.colorScheme.onSurfaceVariant),
                ]),
              ),
            ),
          ],
        ),
        // Vommet: automatic media download per connection (phones only).
        if (MediaAutoDownload.tracksNetwork) const AutoDownloadCard(),
      ],
    );
  }
}

/// Vommet: what the media cache holds by type (a donut and a list), clearing
/// chosen types, and the "Media cache limit" and "Remove media not opened
/// for" sliders. Messages and keys live in other databases and are never
/// cleared here.
class StorageUsagePage extends StatefulWidget {
  const StorageUsagePage({super.key});

  /// "Remove media not opened for" steps, in days (0 = forever).
  static const keepDaysSteps = <double>[1, 3, 5, 7, 14, 30, 0];

  /// "Media cache limit" steps, in MB (0 = unlimited).
  static const limitMbSteps = <double>[500, 1024, 2048, 5120, 10240, 0];

  /// The step closest to [value] (an exact 0 only matches 0).
  static int nearestStep(List<double> steps, double value) {
    if (value <= 0) return steps.indexOf(0);
    var best = 0;
    for (var i = 0; i < steps.length; i++) {
      if (steps[i] <= 0) continue;
      if ((steps[i] - value).abs() < (steps[best] - value).abs()) best = i;
    }
    return best;
  }

  @override
  State<StorageUsagePage> createState() => _StorageUsagePageState();
}

class _StorageUsagePageState extends State<StorageUsagePage> {
  String get labelStorageUsageTitle => Intl.message("Storage usage",
      desc: "Title of the page showing what the media cache uses",
      name: "labelStorageUsageTitle");

  String get labelCacheImages => Intl.message("Images",
      desc: "Cached images in storage usage", name: "labelCacheImages");

  String get labelCacheVideos => Intl.message("Videos",
      desc: "Cached videos in storage usage", name: "labelCacheVideos");

  String get labelCacheGifs => Intl.message("GIFs",
      desc: "Cached GIFs in storage usage", name: "labelCacheGifs");

  String get labelCacheFiles => Intl.message("Files",
      desc: "Cached files in storage usage", name: "labelCacheFiles");

  String get labelCacheOther => Intl.message("Other",
      desc: "Cached voice messages, audio and anything else in storage usage",
      name: "labelCacheOther");

  String labelClearSelected(String size) =>
      Intl.message("Clear selected  $size",
          desc: "Button deleting the chosen types of cached media",
          args: [size],
          name: "labelClearSelected");

  String get labelClearMediaCacheTitle => Intl.message("Clear media cache",
      desc: "Title of the dialog confirming cached media is deleted",
      name: "labelClearMediaCacheTitle");

  String get labelClearMediaCachePrompt => Intl.message(
      "Delete the selected cached media? It downloads again when you open it. Your messages, encryption keys, and saved files are not affected.",
      desc: "Confirmation prompt before deleting cached media",
      name: "labelClearMediaCachePrompt");

  String get labelClear => Intl.message("Clear",
      desc: "Confirms deleting cached media", name: "labelClear");

  String get labelCancel => Intl.message("Cancel",
      desc: "Cancels deleting cached media", name: "labelCancel");

  String labelDatabaseSize(String size) => Intl.message(
      "Vommet's database (messages, keys) uses $size more and is not cleared here.",
      desc: "Explains the database is separate from the media cache",
      args: [size],
      name: "labelDatabaseSize");

  String get labelMediaRedownloads => Intl.message(
      "Media stays on your homeserver and downloads again when you open it.",
      desc: "Explains cleared media can be downloaded again",
      name: "labelMediaRedownloads");

  String get labelLimits => Intl.message("Limits",
      desc: "Header for the media cache limits", name: "labelLimits");

  String get labelMediaCacheLimit => Intl.message("Media cache limit",
      desc: "Slider for the maximum media cache size",
      name: "labelMediaCacheLimit");

  String get labelRemoveMediaNotOpenedFor =>
      Intl.message("Remove media not opened for",
          desc: "Slider for how long unused cached media is kept",
          name: "labelRemoveMediaNotOpenedFor");

  String get labelLimitsDescription => Intl.message(
      "Over the limit, the media you opened longest ago is removed first. Old media is removed shortly after the app starts and when you change these.",
      desc: "Explains how the media cache limits are applied",
      name: "labelLimitsDescription");

  String get labelUnlimited => Intl.message("Unlimited",
      desc: "No media cache size limit", name: "labelUnlimited");

  String get labelForever => Intl.message("Forever",
      desc: "Cached media is never removed for age", name: "labelForever");

  String labelDays(int days) => Intl.plural(days,
      one: "$days day",
      other: "$days days",
      desc: "A number of days for keeping cached media",
      args: [days],
      name: "labelDays");

  String labelWeeks(int weeks) => Intl.plural(weeks,
      one: "$weeks week",
      other: "$weeks weeks",
      desc: "A number of weeks for keeping cached media",
      args: [weeks],
      name: "labelWeeks");

  String get labelOneMonth => Intl.message("1 month",
      desc: "Keep cached media for one month", name: "labelOneMonth");

  Map<CachedMediaType, ({int files, int bytes})>? usage;
  int? databaseBytes;
  final selected = Set<CachedMediaType>.of(CachedMediaType.values);
  bool clearing = false;
  late int keepIndex;
  late int limitIndex;

  @override
  void initState() {
    super.initState();
    keepIndex = StorageUsagePage.nearestStep(
        StorageUsagePage.keepDaysSteps, preferences.mediaCacheKeepDays.value);
    limitIndex = StorageUsagePage.nearestStep(
        StorageUsagePage.limitMbSteps, preferences.mediaCacheLimitMb.value);
    refresh();
  }

  Future<void> refresh() async {
    final result = await fileCache?.usage();
    final db = await fileCache?.databaseSize();
    if (!mounted) return;
    setState(() {
      usage = result;
      databaseBytes = db;
    });
  }

  String typeLabel(CachedMediaType type) => switch (type) {
        CachedMediaType.images => labelCacheImages,
        CachedMediaType.videos => labelCacheVideos,
        CachedMediaType.gifs => labelCacheGifs,
        CachedMediaType.files => labelCacheFiles,
        CachedMediaType.other => labelCacheOther,
      };

  IconData typeIcon(CachedMediaType type) => switch (type) {
        CachedMediaType.images => Icons.image_outlined,
        CachedMediaType.videos => Icons.movie_outlined,
        CachedMediaType.gifs => Icons.gif_box_outlined,
        CachedMediaType.files => Icons.insert_drive_file_outlined,
        CachedMediaType.other => Icons.more_horiz,
      };

  Color typeColor(ColorScheme scheme, CachedMediaType type) => switch (type) {
        CachedMediaType.images => scheme.primary,
        CachedMediaType.videos => scheme.tertiary,
        CachedMediaType.gifs => const Color(0xff7fd18b),
        CachedMediaType.files => const Color(0xfff0a35e),
        CachedMediaType.other => const Color(0xffa3a9b3),
      };

  String keepLabel(double days) {
    if (days <= 0) return labelForever;
    if (days == 30) return labelOneMonth;
    if (days >= 7 && days % 7 == 0) return labelWeeks(days ~/ 7);
    return labelDays(days.round());
  }

  String limitLabel(double mb) => mb <= 0
      ? labelUnlimited
      : FileCache.formatSize((mb * 1024 * 1024).round());

  int get selectedBytes => usage == null
      ? 0
      : selected.fold<int>(0, (a, t) => a + (usage![t]?.bytes ?? 0));

  Future<void> clear() async {
    final confirmed = await AdaptiveDialog.confirmation(context,
        title: labelClearMediaCacheTitle,
        prompt: labelClearMediaCachePrompt,
        confirmationText: labelClear,
        cancelText: labelCancel,
        dangerous: true);
    if (confirmed != true) return;

    final types = selected.length == CachedMediaType.values.length
        ? null
        : Set.of(selected);
    setState(() => clearing = true);
    try {
      await fileCache?.clearAll(types: types);
      await refresh();
    } finally {
      if (mounted) setState(() => clearing = false);
    }
  }

  Future<void> applyLimits() async {
    await fileCache?.clean();
    await refresh();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth > 700;
      final overview = buildOverview(context, wide ? 200 : 180);
      final details = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          buildList(context),
          _Note(labelMediaRedownloads),
          buildLimits(context),
          _Note(labelLimitsDescription),
        ],
      );

      final title = Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Text(labelStorageUsageTitle,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w600)),
      );

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          title,
          if (!wide) ...[overview, details],
          if (wide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 260, child: overview),
                Expanded(child: details),
              ],
            ),
        ],
      );
    });
  }

  Widget buildOverview(BuildContext context, double size) {
    final theme = Theme.of(context);
    final total = usage?.values.fold<int>(0, (a, e) => a + e.bytes) ?? 0;
    final (amount, unit) = splitSize(total);

    return Column(children: [
      const SizedBox(height: 8),
      SizedBox(
        width: size,
        height: size,
        child: Stack(alignment: Alignment.center, children: [
          CustomPaint(
            size: Size(size, size),
            painter: _DonutPainter([
              for (final type in CachedMediaType.values)
                (usage?[type]?.bytes ?? 0, typeColor(theme.colorScheme, type))
            ], theme.colorScheme.surfaceContainerHigh),
          ),
          Column(mainAxisSize: MainAxisSize.min, children: [
            Text(usage == null ? "…" : amount,
                style: theme.textTheme.displaySmall?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w600)),
            if (usage != null)
              Text(unit,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ]),
        ]),
      ),
      const SizedBox(height: 12),
      if (databaseBytes != null)
        _Note(labelDatabaseSize(FileCache.formatSize(databaseBytes!))),
    ]);
  }

  /// "412" and "MB" from a size, for the middle of the donut.
  static (String, String) splitSize(int bytes) {
    final parts = FileCache.formatSize(bytes).split(" ");
    final amount = double.tryParse(parts.first);
    return (
      amount == null ? parts.first : amount.round().toString(),
      parts.last
    );
  }

  Widget buildList(BuildContext context) {
    final theme = Theme.of(context);
    final total = usage?.values.fold<int>(0, (a, e) => a + e.bytes) ?? 0;

    return _SettingsCard(children: [
      const SizedBox(height: 6),
      for (final type in CachedMediaType.values)
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 2, 16, 2),
          child: Row(children: [
            Checkbox(
              value: selected.contains(type),
              onChanged: clearing
                  ? null
                  : (value) => setState(() => value == true
                      ? selected.add(type)
                      : selected.remove(type)),
              fillColor: WidgetStateProperty.resolveWith((states) =>
                  states.contains(WidgetState.selected)
                      ? typeColor(theme.colorScheme, type)
                      : null),
              checkColor: theme.colorScheme.surface,
            ),
            Icon(typeIcon(type),
                size: 18, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Text(typeLabel(type),
                style: theme.textTheme.bodyLarge
                    ?.copyWith(color: theme.colorScheme.onSurface)),
            const SizedBox(width: 8),
            if (total > 0)
              Text("${(100 * (usage?[type]?.bytes ?? 0) / total).round()}%",
                  style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600)),
            const Spacer(),
            Text(FileCache.formatSize(usage?[type]?.bytes ?? 0),
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.primary)),
          ]),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: SizedBox(
          height: 44,
          child: FilledButton(
            onPressed:
                clearing || usage == null || selectedBytes == 0 ? null : clear,
            style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError),
            child: clearing
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: theme.colorScheme.onError))
                : Text(labelClearSelected(FileCache.formatSize(selectedBytes)),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ),
      ),
    ]);
  }

  Widget buildLimits(BuildContext context) {
    final limitSteps = StorageUsagePage.limitMbSteps;
    final keepSteps = StorageUsagePage.keepDaysSteps;
    return _SettingsCard(title: labelLimits, children: [
      _StepSlider(
        label: labelMediaCacheLimit,
        value: limitLabel(limitSteps[limitIndex]),
        index: limitIndex,
        steps: limitSteps.length,
        onChanged: (i) => setState(() => limitIndex = i),
        onChangeEnd: (i) async {
          await preferences.mediaCacheLimitMb.set(limitSteps[i]);
          await applyLimits();
        },
      ),
      _StepSlider(
        label: labelRemoveMediaNotOpenedFor,
        value: keepLabel(keepSteps[keepIndex]),
        index: keepIndex,
        steps: keepSteps.length,
        onChanged: (i) => setState(() => keepIndex = i),
        onChangeEnd: (i) async {
          await preferences.mediaCacheKeepDays.set(keepSteps[i]);
          await applyLimits();
        },
      ),
      const SizedBox(height: 6),
    ]);
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({this.title, required this.children});
  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Text(title!,
                style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600)),
          ),
        ...children,
      ]),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 14),
      child: Text(text,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
    );
  }
}

class _StepSlider extends StatelessWidget {
  const _StepSlider({
    required this.label,
    required this.value,
    required this.index,
    required this.steps,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final String label;
  final String value;
  final int index;
  final int steps;
  final void Function(int) onChanged;
  final void Function(int) onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(label,
                style: theme.textTheme.bodyLarge
                    ?.copyWith(color: theme.colorScheme.onSurface)),
          ),
          Text(value,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.primary)),
        ]),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
              trackHeight: 3, overlayShape: SliderComponentShape.noOverlay),
          child: Slider(
            value: index.toDouble(),
            min: 0,
            max: (steps - 1).toDouble(),
            divisions: steps - 1,
            onChanged: (v) => onChanged(v.round()),
            onChangeEnd: (v) => onChangeEnd(v.round()),
          ),
        ),
        const SizedBox(height: 6),
      ]),
    );
  }
}

/// A ring split into one arc per (size, colour) slice, with small gaps.
class _DonutPainter extends CustomPainter {
  _DonutPainter(this.slices, this.track);
  final List<(int, Color)> slices;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.16;
    final rect = Rect.fromCircle(
        center: size.center(Offset.zero), radius: (size.width - stroke) / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;

    final total = slices.fold<int>(0, (a, s) => a + s.$1);
    if (total == 0) {
      canvas.drawArc(rect, 0, 2 * math.pi, false, paint..color = track);
      return;
    }

    final shown = slices.where((s) => s.$1 > 0).length;
    final gap = shown > 1 ? 0.035 : 0.0;
    var start = -math.pi / 2;
    for (final (bytes, color) in slices) {
      if (bytes == 0) continue;
      final sweep = 2 * math.pi * bytes / total;
      canvas.drawArc(rect, start + gap / 2, math.max(sweep - gap, 0.01), false,
          paint..color = color);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) =>
      oldDelegate.slices.length != slices.length ||
      oldDelegate.track != track ||
      Iterable.generate(slices.length)
          .any((i) => oldDelegate.slices[i] != slices[i]);
}
