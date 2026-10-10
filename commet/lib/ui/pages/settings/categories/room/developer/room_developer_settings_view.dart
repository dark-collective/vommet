import 'package:commet/client/room.dart';
import 'package:commet/ui/atoms/code_block.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:commet/main.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class RoomDeveloperSettingsView extends StatelessWidget {
  final Room room;
  const RoomDeveloperSettingsView(this.room, {super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
        children:
            [jsonDump(context), notificationTests(context)].map<Widget>((e) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(0, 3, 0, 3),
        child: ClipRRect(borderRadius: BorderRadius.circular(10), child: e),
      );
    }).toList());
  }

  Widget jsonDump(BuildContext context) {
    return ExpansionTile(
      title: const tiamat.Text.labelEmphasised("Room State"),
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      collapsedBackgroundColor:
          Theme.of(context).colorScheme.surfaceContainerLow,
      children: [_RoomStateDump(room.developerInfo)],
    );
  }

  Widget notificationTests(BuildContext context) {
    return ExpansionTile(
      title: const tiamat.Text.labelEmphasised("Shortcuts"),
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      collapsedBackgroundColor:
          Theme.of(context).colorScheme.surfaceContainerLow,
      children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          tiamat.Button(
            text: "Register Shortcut",
            onTap: () => shortcutsManager.createShortcutForRoom(room),
          ),
          tiamat.Button(
            text: "Clear All Shortcuts",
            onTap: () => shortcutsManager.clearAllShortcuts(),
          ),
        ])
      ],
    );
  }
}

/// Vommet: a big room's state (every member event) is megabytes of JSON;
/// highlighting and laying it out in one block froze the app until Android
/// killed it (ANR, tester report on a large public room). Highlight only
/// small dumps, show at most [showLimit] characters, and offer the full text
/// on the clipboard.
class _RoomStateDump extends StatelessWidget {
  const _RoomStateDump(this.json);

  final String json;

  static const highlightLimit = 50000;
  static const showLimit = 150000;

  @override
  Widget build(BuildContext context) {
    if (json.length <= highlightLimit) {
      return SelectionArea(child: Codeblock(language: "json", text: json));
    }

    final shown = json.length > showLimit ? json.substring(0, showLimit) : json;
    final kb = (json.length / 1024).round();
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Row(
            spacing: 8,
            children: [
              Expanded(
                child: tiamat.Text.labelLow(json.length > showLimit
                    ? "Large room state ($kb KB): showing the first "
                        "${showLimit ~/ 1000}k characters, without highlighting."
                    : "Large room state ($kb KB), shown without highlighting."),
              ),
              tiamat.Button(
                text: "Copy full JSON",
                onTap: () => Clipboard.setData(ClipboardData(text: json)),
              ),
            ],
          ),
          SelectableText(
            shown,
            style: const TextStyle(fontFamily: "monospace", fontSize: 12),
          ),
        ],
      ),
    );
  }
}
