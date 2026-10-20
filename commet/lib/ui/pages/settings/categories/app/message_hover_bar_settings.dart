import 'package:commet/ui/molecules/room_timeline_widget/message_hover_bar.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet: Settings › Appearance › Message actions on hover.
class MessageHoverBarSettings extends StatefulWidget {
  const MessageHoverBarSettings({super.key});

  @override
  State<MessageHoverBarSettings> createState() =>
      _MessageHoverBarSettingsState();
}

class _MessageHoverBarSettingsState extends State<MessageHoverBarSettings> {
  String get labelMessageHoverBar => Intl.message("Message actions on hover",
      name: "labelMessageHoverBar",
      desc: "Header of the setting for the bar shown over a message you "
          "point at");

  String get labelMessageHoverBarHelp => Intl.message(
      "The bar that appears over a message when you point at it. "
      "Right-click a message for every action, whatever you pick here.",
      name: "labelMessageHoverBarHelp",
      desc: "Explains the message hover bar setting");

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dim = theme.colorScheme.onSurfaceVariant;
    return tiamat.Panel(
      header: labelMessageHoverBar,
      mode: tiamat.TileType.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            tiamat.Text.labelLow(labelMessageHoverBarHelp),
            RadioGroup<MessageHoverBar>(
              groupValue: MessageHoverBar.current,
              onChanged: (value) async {
                if (value == null) return;
                await MessageHoverBar.preference.set(value.name);
                if (mounted) setState(() {});
              },
              child: Column(
                children: [
                  for (final option in MessageHoverBar.values)
                    RadioListTile<MessageHoverBar>(
                      key: ValueKey("message-hover-bar-${option.name}"),
                      value: option,
                      contentPadding: EdgeInsets.zero,
                      title: Text(option.label),
                      subtitle: Text(option.description,
                          style:
                              theme.textTheme.bodySmall?.copyWith(color: dim)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
