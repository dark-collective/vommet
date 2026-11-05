import 'package:commet/config/message_density.dart';
import 'package:commet/ui/pages/settings/search/settings_search.dart';
import 'package:commet/ui/pages/setup/onboarding/choice_cards.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:tiamat/tiamat.dart';

/// Vommet: Settings › Appearance › Message spacing (Vommet issue 524).
class MessageDensitySettings extends StatelessWidget {
  const MessageDensitySettings({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsSearchTarget(
      ids: [messageDensityPreference.key, messageDensityTitle],
      child: Panel(
        header: messageDensityTitle,
        mode: TileType.surfaceContainerLow,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 8,
            children: [
              tiamat.Text.labelLow(messageDensitySettingsDescription),
              const MessageDensityPicker(),
            ],
          ),
        ),
      ),
    );
  }
}

String get messageDensitySettingsDescription => Intl.message(
    "How tightly messages are packed in a room. Rooms you have open change when you next scroll or open them.",
    name: "messageDensitySettingsDescription",
    desc: "Explains the message spacing setting in Settings › Appearance");

/// Cozy and Compact as cards with a picture each; picking one saves it.
class MessageDensityPicker extends StatefulWidget {
  const MessageDensityPicker({super.key});

  @override
  State<MessageDensityPicker> createState() => _MessageDensityPickerState();
}

class _MessageDensityPickerState extends State<MessageDensityPicker> {
  @override
  Widget build(BuildContext context) {
    return ChoiceCards<MessageDensity>(
      selected: messageDensity,
      onSelected: (d) async {
        await messageDensityPreference.set(d.name);
        if (mounted) setState(() {});
      },
      options: [
        for (final d in MessageDensity.values)
          ChoiceCardOption(
            value: d,
            title: d.label,
            description: d.description,
            preview: MessageDensityPreview(density: d),
          ),
      ],
    );
  }
}

/// A few made-up messages spaced as [density] spaces them.
class MessageDensityPreview extends StatelessWidget {
  const MessageDensityPreview({required this.density, super.key});
  final MessageDensity density;

  static const _rowan = Color(0xff7fd1a8);
  static const _kit = Color(0xffc58cff);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget message(String name, Color color, List<String> lines) => Padding(
          padding: EdgeInsets.symmetric(vertical: density.verticalPadding),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              tiamat.Avatar(
                  placeholderText: name,
                  placeholderColor: color,
                  radius: density.avatarSize / 2),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    tiamat.Text.name(name, color: color),
                    for (final l in lines)
                      Padding(
                        padding:
                            EdgeInsets.only(top: density.verticalPadding * 2),
                        child: tiamat.Text(l,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
    return Container(
      key: ValueKey("message-density-preview-${density.name}"),
      decoration: BoxDecoration(
          color: scheme.surface, borderRadius: BorderRadius.circular(8)),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          message("Rowan", _rowan, [messageDensitySampleFirst]),
          message("Kit", _kit,
              [messageDensitySampleSecond, messageDensitySampleThird]),
        ],
      ),
    );
  }
}

String get messageDensitySampleFirst => Intl.message("Anyone up for a game?",
    name: "messageDensitySampleFirst",
    desc: "Made-up message in the message spacing preview");

String get messageDensitySampleSecond =>
    Intl.message("Me! Give me five minutes",
        name: "messageDensitySampleSecond",
        desc: "Made-up message in the message spacing preview");

String get messageDensitySampleThird => Intl.message("Starting a call now",
    name: "messageDensitySampleThird",
    desc: "Made-up message in the message spacing preview");
