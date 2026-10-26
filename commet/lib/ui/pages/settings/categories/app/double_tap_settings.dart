import 'package:commet/ui/molecules/timeline_events/double_tap_action.dart';
import 'package:commet/ui/pages/settings/search/settings_search.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:tiamat/tiamat.dart' hide Text;

/// Vommet (experiment): Settings › Appearance › Double-tap.
class DoubleTapSettings extends StatefulWidget {
  const DoubleTapSettings({super.key});

  /// The reactions to pick from.
  static const reactions = ["❤️", "👍", "😂", "🔥", "👀", "🎉", "😮", "😢"];

  @override
  State<DoubleTapSettings> createState() => _DoubleTapSettingsState();
}

class _DoubleTapSettingsState extends State<DoubleTapSettings> {
  @override
  Widget build(BuildContext context) {
    final action = DoubleTapAction.parse(doubleTapActionPreference.value,
        phone: DoubleTapAction.isPhone);
    final reaction = doubleTapReactionPreference.value;
    return SettingsSearchTarget(
      ids: [doubleTapActionPreference.key, doubleTapSettingsHeader],
      child: Panel(
        header: doubleTapSettingsHeader,
        mode: TileType.surfaceContainerLow,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 8,
            children: [
              tiamat.Text(doubleTapSettingsTitle),
              tiamat.Text.labelLow(doubleTapSettingsDescription),
              tiamat.DropdownSelector<DoubleTapAction>(
                color: ColorScheme.of(context).surfaceContainerLow,
                items: DoubleTapAction.values,
                itemBuilder: (item) => tiamat.Text(item.label),
                onItemSelected: (item) async {
                  if (item == null) return;
                  await doubleTapActionPreference.set(item.name);
                  if (mounted) setState(() {});
                },
                value: action,
              ),
              if (action == DoubleTapAction.react) ...[
                const SizedBox(height: 4),
                tiamat.Text.labelLow(doubleTapSettingsReactWith),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final emoji in DoubleTapSettings.reactions)
                    ChoiceChip(
                      label: Text(emoji, style: const TextStyle(fontSize: 18)),
                      selected: DoubleTapAction.sameEmoji(emoji, reaction),
                      onSelected: (_) async {
                        await doubleTapReactionPreference.set(emoji);
                        if (mounted) setState(() {});
                      },
                    ),
                ]),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
