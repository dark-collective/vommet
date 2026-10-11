import 'package:commet/main.dart';
import 'package:commet/ui/atoms/thread_card.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:tiamat/tiamat.dart';

/// Vommet: Settings › Appearance › Threads.
class ThreadPreviewSettings extends StatefulWidget {
  const ThreadPreviewSettings({super.key});

  @override
  State<ThreadPreviewSettings> createState() => _ThreadPreviewSettingsState();
}

class _ThreadPreviewSettingsState extends State<ThreadPreviewSettings> {
  @override
  Widget build(BuildContext context) {
    return Panel(
      header: "Threads",
      mode: TileType.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 8,
          children: [
            const tiamat.Text("Thread previews"),
            const tiamat.Text.labelLow(
                "Which replies the card under a thread's first message shows"),
            tiamat.DropdownSelector<ThreadPreviewMode>(
              color: ColorScheme.of(context).surfaceContainerLow,
              items: ThreadPreviewMode.values,
              itemBuilder: (item) => tiamat.Text(item.label),
              onItemSelected: (item) async {
                if (item == null) return;
                await preferences.threadPreviewMode.set(item.name);
                if (mounted) setState(() {});
              },
              value:
                  ThreadPreviewMode.parse(preferences.threadPreviewMode.value),
            ),
          ],
        ),
      ),
    );
  }
}
