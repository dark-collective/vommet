import 'package:commet/client/client.dart';
import 'package:commet/client/matrix/forwarding/matrix_forwarding.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/ui/organisms/message_selection/message_selection.dart';
import 'package:commet/utils/common_strings.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet: stands in for the room header while messages are selected.
class MessageSelectionBar extends StatelessWidget {
  const MessageSelectionBar(this.selection, {super.key});

  final MessageSelection selection;

  /// The selection bar while [room] has messages selected, otherwise
  /// [header].
  static Widget orHeader(
      Room room, Widget Function(BuildContext context) header) {
    return ValueListenableBuilder(
      valueListenable: MessageSelection.changed,
      builder: (context, _, __) {
        final selection = MessageSelection.activeIn(room);
        return selection == null
            ? header(context)
            : MessageSelectionBar(selection);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: selection,
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) =>
            MediaQuery.of(context).mobile || constraints.maxWidth < 520
                ? buildCompact(context)
                : buildWide(context),
      ),
    );
  }

  String get label =>
      selection.progress ?? "${selection.ticked.length} selected";

  Widget buildWide(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final busy = selection.busy;
    final deletable = selection.deletableCount;
    final forwardable = selection.forwardableEvents().length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 10, 0),
      child: Row(
        children: [
          Expanded(
            child: tiamat.Text.label(label,
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          if (MatrixForwarding.enabled)
            TextButton.icon(
              icon: const Icon(Icons.shortcut, size: 18),
              label: Text(forwardable > 0 ? "Forward $forwardable" : "Forward"),
              onPressed: busy || forwardable == 0
                  ? null
                  : () => selection.forward(context),
            ),
          TextButton.icon(
            icon: const Icon(Icons.delete, size: 18),
            label: Text(deletable > 0 ? "Delete $deletable" : "Delete"),
            style: TextButton.styleFrom(foregroundColor: colors.error),
            onPressed:
                busy || deletable == 0 ? null : () => selection.delete(context),
          ),
          TextButton(
            onPressed: busy ? null : selection.exit,
            child: Text(CommonStrings.promptCancel),
          ),
        ],
      ),
    );
  }

  Widget buildCompact(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final busy = selection.busy;
    final deletable = selection.deletableCount;
    final forwardable = selection.forwardableEvents().length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: CommonStrings.promptCancel,
            onPressed: busy ? null : selection.exit,
          ),
          Expanded(
            child: tiamat.Text.label(label,
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: CommonStrings.promptCopy,
            onPressed: busy ? null : selection.copy,
          ),
          if (MatrixForwarding.enabled)
            IconButton(
              icon: const Icon(Icons.shortcut),
              tooltip: "Forward",
              onPressed: busy || forwardable == 0
                  ? null
                  : () => selection.forward(context),
            ),
          IconButton(
            icon: const Icon(Icons.delete),
            tooltip: CommonStrings.promptDelete,
            color: colors.error,
            onPressed:
                busy || deletable == 0 ? null : () => selection.delete(context),
          ),
        ],
      ),
    );
  }
}
