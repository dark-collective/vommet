import 'package:commet/client/client.dart';
import 'package:commet/client/matrix/forwarding/matrix_forwarding.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/ui/organisms/message_selection/message_selection.dart';
import 'package:commet/utils/common_strings.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:intl/intl.dart';

/// Vommet: stands in for the room header while messages are selected.
class MessageSelectionBar extends StatelessWidget {
  static String messageSelectionSelected(int count) => Intl.message(
      "$count selected",
      args: [count],
      name: "messageSelectionSelected",
      desc:
          "Bar shown while selecting several messages: how many messages are ticked");

  static String get messageSelectionForward => Intl.message("Forward",
      name: "messageSelectionForward",
      desc:
          "Bar shown while selecting several messages: button and tooltip that forwards the ticked messages");

  static String messageSelectionForwardCount(int count) => Intl.message(
      "Forward $count",
      args: [count],
      name: "messageSelectionForwardCount",
      desc:
          "Bar shown while selecting several messages: button that forwards the ticked messages; count is how many can be forwarded");

  static String messageSelectionDeleteCount(int count) => Intl.message(
      "Delete $count",
      args: [count],
      name: "messageSelectionDeleteCount",
      desc:
          "Bar shown while selecting several messages: button that deletes the ticked messages; count is how many can be deleted");

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
      selection.progress ?? messageSelectionSelected(selection.ticked.length);

  Widget buildWide(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final busy = selection.busy;
    final deletable = selection.deletableCount;
    final forwardable = selection.forwardableEvents().length;
    final replyable = selection.replyEvent() != null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 10, 0),
      child: Row(
        children: [
          Expanded(
            child: tiamat.Text.label(label,
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          TextButton.icon(
            icon: const Icon(Icons.copy, size: 18),
            label: Text(CommonStrings.promptCopy),
            onPressed: busy ? null : selection.copy,
          ),
          if (MatrixForwarding.enabled)
            TextButton.icon(
              icon: const Icon(Icons.shortcut, size: 18),
              label: Text(forwardable > 0
                  ? messageSelectionForwardCount(forwardable)
                  : messageSelectionForward),
              onPressed: busy || forwardable == 0
                  ? null
                  : () => selection.forward(context),
            ),
          // Vommet issue 895: reply to the first ticked item from the top.
          TextButton.icon(
            icon: const Icon(Icons.reply, size: 18),
            label: Text(CommonStrings.promptReply),
            onPressed: busy || !replyable ? null : selection.reply,
          ),
          TextButton.icon(
            icon: const Icon(Icons.delete, size: 18),
            label: Text(deletable > 0
                ? messageSelectionDeleteCount(deletable)
                : CommonStrings.promptDelete),
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
    final replyable = selection.replyEvent() != null;

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
              tooltip: messageSelectionForward,
              onPressed: busy || forwardable == 0
                  ? null
                  : () => selection.forward(context),
            ),
          IconButton(
            key: const ValueKey("message-selection-reply"),
            icon: const Icon(Icons.reply),
            tooltip: CommonStrings.promptReply,
            onPressed: busy || !replyable ? null : selection.reply,
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
