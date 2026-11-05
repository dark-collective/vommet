import 'dart:math' as math;

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

  static String get messageSelectionDownload => Intl.message("Download",
      name: "messageSelectionDownload",
      desc: "Timeline selection: save selected photos and videos");

  static String messageSelectionDownloadCount(int count) =>
      Intl.message("Download $count",
          args: [count],
          name: "messageSelectionDownloadCount",
          desc: "Timeline selection: number of photos and videos to save");

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
      builder: (context, _) => LayoutBuilder(builder: (context, constraints) {
        final style = Theme.of(context).textTheme.labelLarge!;
        final labels = [
          CommonStrings.promptCopy,
          messageSelectionDownloadCount(selection.downloadableMedia().length),
          if (MatrixForwarding.enabled)
            messageSelectionForwardCount(selection.forwardableEvents().length),
          CommonStrings.promptReply,
          messageSelectionDeleteCount(selection.deletableCount),
          CommonStrings.promptCancel
        ];
        double textWidth(String text) {
          final painter = TextPainter(
              text: TextSpan(text: text, style: style),
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context))
            ..layout();
          return painter.width;
        }

        final wideWidth = labels.fold<double>(
            160, (width, label) => width + textWidth(label) + 60);
        return !MediaQuery.of(context).mobile &&
                constraints.maxWidth >= math.max(520, wideWidth)
            ? buildWide(context)
            : buildCompact(context, width: constraints.maxWidth);
      }),
    );
  }

  String get label =>
      selection.progress ?? messageSelectionSelected(selection.ticked.length);

  Widget _count({bool short = false}) => Expanded(
        child: Semantics(
            liveRegion: selection.busy,
            label: label,
            child: Tooltip(
                message: label,
                excludeFromSemantics: true,
                child: ExcludeSemantics(
                    child: tiamat.Text.label(
                        short && !selection.busy
                            ? selection.ticked.length.toString()
                            : label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis)))),
      );

  Widget buildWide(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final busy = selection.busy;
    final deletable = selection.deletableCount;
    final forwardable = selection.forwardableEvents().length;
    final replyable = selection.replyEvent() != null;
    final media = selection.downloadableMedia().length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 10, 0),
      child: Row(children: [
        _count(),
        TextButton.icon(
            icon: const Icon(Icons.copy, size: 18),
            label: Text(CommonStrings.promptCopy),
            onPressed: busy ? null : selection.copy),
        TextButton.icon(
            key: const ValueKey("message-selection-download"),
            icon: const Icon(Icons.download_outlined, size: 18),
            label: Text(media > 0
                ? messageSelectionDownloadCount(media)
                : messageSelectionDownload),
            onPressed:
                busy || media == 0 ? null : () => selection.save(context)),
        if (MatrixForwarding.enabled)
          TextButton.icon(
              icon: const Icon(Icons.shortcut, size: 18),
              label: Text(forwardable > 0
                  ? messageSelectionForwardCount(forwardable)
                  : messageSelectionForward),
              onPressed: busy || forwardable == 0
                  ? null
                  : () => selection.forward(context)),
        TextButton.icon(
            key: const ValueKey("message-selection-reply"),
            icon: const Icon(Icons.reply, size: 18),
            label: Text(CommonStrings.promptReply),
            onPressed: busy || !replyable ? null : selection.reply),
        TextButton.icon(
            icon: const Icon(Icons.delete, size: 18),
            label: Text(deletable > 0
                ? messageSelectionDeleteCount(deletable)
                : CommonStrings.promptDelete),
            style: TextButton.styleFrom(foregroundColor: colors.error),
            onPressed: busy || deletable == 0
                ? null
                : () => selection.delete(context)),
        TextButton(
            onPressed: busy ? null : selection.exit,
            child: Text(CommonStrings.promptCancel)),
      ]),
    );
  }

  Widget buildCompact(BuildContext context, {double width = 520}) {
    final colors = Theme.of(context).colorScheme;
    final busy = selection.busy;
    final deletable = selection.deletableCount;
    final forwardable = selection.forwardableEvents().length;
    final replyable = selection.replyEvent() != null;
    final media = selection.downloadableMedia().length;
    final largeText = MediaQuery.textScalerOf(context).scale(16) > 20;
    // Phones (360 dp and up) keep Reply and Delete as one-tap icons; the
    // menu is for very narrow bars and large text only.
    final overflow = width < 320 || largeText;
    final hideForward = overflow && (width < 300 || largeText);
    final hideClose = width < 240;
    // Preserve the number at large text sizes, with the full label available
    // to screen readers and in the tooltip. Keep every action target at 48 px.
    final shortCount = width < 360 && largeText || hideClose;
    Widget icon(IconData icon, String tooltip, VoidCallback? onPressed,
            {Key? key, Color? color}) =>
        SizedBox(
            width: 48,
            height: 48,
            child: IconButton(
                key: key,
                icon: Icon(icon,
                    color: onPressed == null
                        ? colors.onSurface.withAlpha(97)
                        : color),
                tooltip: tooltip,
                color: color,
                disabledColor: colors.onSurface.withAlpha(97),
                onPressed: onPressed));
    Widget menuItem(IconData icon, String text, {bool danger = false}) =>
        Row(children: [
          Icon(icon, size: 20, color: danger ? colors.error : null),
          const SizedBox(width: 12),
          Flexible(child: Text(text)),
        ]);
    final row = Row(children: [
      if (!hideClose)
        icon(Icons.close, CommonStrings.promptCancel,
            busy ? null : selection.exit),
      _count(short: shortCount),
      icon(Icons.copy, CommonStrings.promptCopy, busy ? null : selection.copy),
      icon(
          Icons.download_outlined,
          media > 0
              ? messageSelectionDownloadCount(media)
              : messageSelectionDownload,
          busy || media == 0 ? null : () => selection.save(context),
          key: const ValueKey("message-selection-download")),
      if (MatrixForwarding.enabled && !hideForward)
        icon(Icons.shortcut, messageSelectionForward,
            busy || forwardable == 0 ? null : () => selection.forward(context)),
      if (!overflow) ...[
        icon(Icons.reply, CommonStrings.promptReply,
            busy || !replyable ? null : selection.reply,
            key: const ValueKey("message-selection-reply")),
        icon(Icons.delete, CommonStrings.promptDelete,
            busy || deletable == 0 ? null : () => selection.delete(context),
            color: colors.error),
      ],
      if (overflow)
        SizedBox(
            width: 48,
            height: 48,
            child: PopupMenuButton<_SelectionAction>(
              key: const ValueKey("message-selection-more"),
              enabled: !busy,
              icon: Icon(Icons.more_vert,
                  color: busy ? colors.onSurface.withAlpha(97) : null),
              onSelected: (action) {
                if (selection.busy) return;
                switch (action) {
                  case _SelectionAction.forward:
                    selection.forward(context);
                  case _SelectionAction.reply:
                    selection.reply();
                  case _SelectionAction.delete:
                    selection.delete(context);
                  case _SelectionAction.cancel:
                    selection.exit();
                }
              },
              itemBuilder: (_) => [
                if (MatrixForwarding.enabled && hideForward)
                  PopupMenuItem(
                      value: _SelectionAction.forward,
                      enabled: forwardable > 0,
                      child: menuItem(
                          Icons.shortcut,
                          forwardable > 0
                              ? messageSelectionForwardCount(forwardable)
                              : messageSelectionForward)),
                PopupMenuItem(
                    value: _SelectionAction.reply,
                    enabled: replyable,
                    child: menuItem(Icons.reply, CommonStrings.promptReply)),
                PopupMenuItem(
                    value: _SelectionAction.delete,
                    enabled: deletable > 0,
                    child: menuItem(
                        Icons.delete,
                        deletable > 0
                            ? messageSelectionDeleteCount(deletable)
                            : CommonStrings.promptDelete,
                        danger: true)),
                if (hideClose)
                  PopupMenuItem(
                      value: _SelectionAction.cancel,
                      child: menuItem(Icons.close, CommonStrings.promptCancel)),
              ],
            )),
    ]);
    return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: width < 180
            ? SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(width: 180, child: row))
            : row);
  }
}

enum _SelectionAction { forward, reply, delete, cancel }
