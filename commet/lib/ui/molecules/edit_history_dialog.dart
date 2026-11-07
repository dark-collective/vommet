import 'package:commet/client/timeline.dart';
import 'package:commet/client/timeline_events/timeline_event_message.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/utils/text_utils.dart';
import 'package:commet/utils/word_diff.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet (chat navigation): every version of an edited message, newest
/// first, each marked with what changed from the version before it.
class EditHistoryDialog extends StatefulWidget {
  const EditHistoryDialog(
      {required this.event, required this.timeline, super.key});
  final TimelineEventMessage event;
  final Timeline timeline;

  static String get promptEditHistory => Intl.message("Edit history",
      desc:
          "Menu option and dialog title that shows the earlier versions of an edited message",
      name: "promptEditHistory");

  static String get labelEditHistoryShowChanges => Intl.message("Show changes",
      desc:
          "Switch in the edit history that marks what each version added and removed",
      name: "labelEditHistoryShowChanges");

  static String get labelEditHistoryCurrent => Intl.message("Current",
      desc: "Marks the newest version of a message in its edit history",
      name: "labelEditHistoryCurrent");

  static String get labelEditHistoryOriginal => Intl.message("Original",
      desc: "Marks the first version of a message in its edit history",
      name: "labelEditHistoryOriginal");

  static String get labelEditHistoryFailed => Intl.message(
      "Couldn't load the edit history",
      desc: "Shown in the edit history when its versions couldn't be loaded",
      name: "labelEditHistoryFailed");

  static Future<void> show(BuildContext context,
      {required TimelineEventMessage event, required Timeline timeline}) {
    return AdaptiveDialog.show(context,
        title: promptEditHistory,
        builder: (_) => EditHistoryDialog(event: event, timeline: timeline));
  }

  @override
  State<EditHistoryDialog> createState() => _EditHistoryDialogState();
}

class _EditHistoryDialogState extends State<EditHistoryDialog> {
  late final Future<List<MessageVersion>> versions =
      widget.event.getEditHistory(widget.timeline);
  bool showChanges = true;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: FutureBuilder(
        future: versions,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: tiamat.Text.labelLow(
                  EditHistoryDialog.labelEditHistoryFailed),
            );
          }
          final list = snapshot.data;
          if (list == null) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (list.length > 1)
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    tiamat.Text.labelLow(
                        EditHistoryDialog.labelEditHistoryShowChanges),
                    const SizedBox(width: 8),
                    tiamat.Switch(
                      state: showChanges,
                      onChanged: (v) => setState(() => showChanges = v),
                    ),
                  ],
                ),
              for (var i = 0; i < list.length; i++)
                versionTile(context, list, i),
            ],
          );
        },
      ),
    );
  }

  Widget versionTile(BuildContext context, List<MessageVersion> list, int i) {
    final version = list[i];
    final colors = Theme.of(context).colorScheme;
    final tag = i == 0
        ? EditHistoryDialog.labelEditHistoryCurrent
        : i == list.length - 1
            ? EditHistoryDialog.labelEditHistoryOriginal
            : null;
    final older = i + 1 < list.length ? list[i + 1] : null;

    Widget body;
    if (showChanges && older != null) {
      final style = DefaultTextStyle.of(context).style;
      body = Text.rich(TextSpan(children: [
        for (final part in WordDiff.diff(older.body, version.body))
          TextSpan(
            text: part.text,
            style: switch (part.kind) {
              WordDiffKind.same => null,
              WordDiffKind.added => TextStyle(
                  backgroundColor: Colors.green.withAlpha(60),
                ),
              WordDiffKind.removed => TextStyle(
                  decoration: TextDecoration.lineThrough,
                  color: colors.error,
                ),
            },
          ),
      ], style: style.copyWith(color: colors.onSurface)));
    } else {
      body = tiamat.Text(version.body);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            tiamat.Text.labelLow(TextUtils.timestampToLocalizedTimeSpecific(
                version.time, context)),
            if (tag != null) ...[
              const SizedBox(width: 8),
              tiamat.Text.labelEmphasised(tag),
            ],
          ]),
          const SizedBox(height: 4),
          SelectionArea(child: body),
          if (i + 1 < list.length) const Divider(height: 16),
        ],
      ),
    );
  }
}
