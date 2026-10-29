import 'package:commet/config/timeline_image_size.dart';
import 'package:commet/ui/pages/settings/search/settings_search.dart';
import 'package:commet/ui/pages/setup/onboarding/choice_cards.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:tiamat/tiamat.dart';

/// Vommet: Settings › Appearance › Image size in the timeline (Vommet issue
/// 721).
class TimelineImageSizeSettings extends StatelessWidget {
  const TimelineImageSizeSettings({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsSearchTarget(
      ids: [timelineImageSizePreference.key, timelineImageSizeTitle],
      child: Panel(
        header: timelineImageSizeTitle,
        mode: TileType.surfaceContainerLow,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 8,
            children: [
              tiamat.Text.labelLow(timelineImageSizeSettingsDescription),
              const TimelineImageSizePicker(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Default and Large as cards with a picture each; picking one saves it.
class TimelineImageSizePicker extends StatefulWidget {
  const TimelineImageSizePicker({super.key});

  @override
  State<TimelineImageSizePicker> createState() =>
      _TimelineImageSizePickerState();
}

class _TimelineImageSizePickerState extends State<TimelineImageSizePicker> {
  @override
  Widget build(BuildContext context) {
    return ChoiceCards<TimelineImageSize>(
      selected: timelineImageSize,
      onSelected: (s) async {
        await timelineImageSizePreference.set(s.name);
        if (mounted) setState(() {});
      },
      options: [
        for (final s in TimelineImageSize.values)
          ChoiceCardOption(
            value: s,
            title: s.label,
            description: s.description,
            preview: TimelineImageSizePreview(size: s),
          ),
      ],
    );
  }
}

/// A made-up message with a picture shown at [size].
class TimelineImageSizePreview extends StatelessWidget {
  const TimelineImageSizePreview({required this.size, super.key});
  final TimelineImageSize size;

  static const _avatar = Color(0xffc58cff);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final large = size == TimelineImageSize.large;
    final picture = Container(
      height: large ? 96 : 44,
      width: large ? double.infinity : 66,
      decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: BorderRadius.circular(6)),
      child: Icon(Icons.landscape_rounded,
          size: large ? 48 : 24, color: scheme.onPrimaryContainer),
    );
    return Container(
      key: ValueKey("timeline-image-size-preview-${size.name}"),
      decoration: BoxDecoration(
          color: scheme.surface, borderRadius: BorderRadius.circular(8)),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const tiamat.Avatar(
              placeholderText: "R", placeholderColor: _avatar, radius: 12),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 6,
              children: [
                Container(
                  height: 8,
                  width: 96,
                  decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4)),
                ),
                picture,
              ],
            ),
          ),
        ],
      ),
    );
  }
}
