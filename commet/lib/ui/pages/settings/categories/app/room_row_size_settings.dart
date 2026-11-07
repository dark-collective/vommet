import 'package:commet/config/room_row_size.dart';
import 'package:commet/ui/pages/settings/search/settings_search.dart';
import 'package:commet/ui/pages/setup/onboarding/choice_cards.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:tiamat/tiamat.dart';

/// Vommet: Settings › Appearance › Room row size (Vommet issue 796).
class RoomRowSizeSettings extends StatelessWidget {
  const RoomRowSizeSettings({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsSearchTarget(
      ids: [roomRowSizePreference.key, roomRowSizeTitle],
      child: Panel(
        header: roomRowSizeTitle,
        mode: TileType.surfaceContainerLow,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 8,
            children: [
              tiamat.Text.labelLow(roomRowSizeDescription),
              const RoomRowSizePicker(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Standard and Large as cards with a picture each; picking one saves it.
class RoomRowSizePicker extends StatefulWidget {
  const RoomRowSizePicker({super.key});

  @override
  State<RoomRowSizePicker> createState() => _RoomRowSizePickerState();
}

class _RoomRowSizePickerState extends State<RoomRowSizePicker> {
  @override
  Widget build(BuildContext context) {
    return ChoiceCards<RoomRowSize>(
      selected: roomRowSize,
      onSelected: (s) async {
        await roomRowSizePreference.set(s.name);
        if (mounted) setState(() {});
      },
      options: [
        for (final s in RoomRowSize.values)
          ChoiceCardOption(
            value: s,
            title: s.label,
            description: s.description,
            preview: RoomRowSizePreview(size: s),
          ),
      ],
    );
  }
}

/// A few made-up rooms sized as [size] sizes them.
class RoomRowSizePreview extends StatelessWidget {
  const RoomRowSizePreview({required this.size, super.key});
  final RoomRowSize size;

  static const _colors = [Color(0xff7fd1a8), Color(0xffc58cff)];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final names = [roomRowSizeSampleFirst, roomRowSizeSampleSecond];
    return Container(
      key: ValueKey("room-row-size-preview-${size.name}"),
      decoration: BoxDecoration(
          color: scheme.surface, borderRadius: BorderRadius.circular(8)),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(
            textScaler: size.textScaler(MediaQuery.textScalerOf(context))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: size.rowGap,
          children: [
            for (var i = 0; i < names.length; i++)
              Padding(
                padding: size.rowPadding,
                child: Row(children: [
                  tiamat.Avatar(
                      placeholderText: names[i],
                      placeholderColor: _colors[i],
                      radius: size.panelAvatarRadius),
                  const SizedBox(width: 8),
                  Expanded(
                      child: tiamat.Text.labelEmphasised(names[i],
                          maxLines: 1, overflow: TextOverflow.ellipsis)),
                ]),
              ),
          ],
        ),
      ),
    );
  }
}

String get roomRowSizeSampleFirst => Intl.message("Game night",
    name: "roomRowSizeSampleFirst",
    desc: "Made-up room name in the room row size preview");

String get roomRowSizeSampleSecond => Intl.message("Rowan",
    name: "roomRowSizeSampleSecond",
    desc: "Made-up person's name in the room row size preview");
