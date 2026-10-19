import 'package:commet/ui/atoms/redaction_scope.dart';
import 'package:commet/ui/molecules/timeline_events/layouts/timeline_event_layout_message.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet: chat-bubble layout for a message (Vommet issue 421), opt-in via
/// `preferences.chatBubbleLayout`. Your own messages sit on the right,
/// everyone else's on the left. It draws the parts of [message] (the list
/// layout's widget, built as usual) in bubbles, so every part the list layout
/// gains shows up here too.
class TimelineEventLayoutBubble extends StatelessWidget {
  const TimelineEventLayoutBubble(
      {super.key,
      required this.message,
      required this.isOwnMessage,
      required this.isDirectMessage});

  final TimelineEventLayoutMessage message;
  final bool isOwnMessage;
  final bool isDirectMessage;

  /// Bubbles never grow wider than this share of the timeline.
  static const double maxWidthFraction = 0.75;

  /// Avatars (and the space they take) only on other people's messages in
  /// group rooms.
  static bool showsAvatarColumn(
          {required bool isOwnMessage, required bool isDirectMessage}) =>
      !isOwnMessage && !isDirectMessage;

  /// The name and avatar go on the first bubble of a run, in group rooms
  /// only, never on your own bubbles.
  static bool showsName(
          {required bool isOwnMessage,
          required bool isDirectMessage,
          required bool showSender}) =>
      showSender &&
      showsAvatarColumn(
          isOwnMessage: isOwnMessage, isDirectMessage: isDirectMessage);

  @override
  Widget build(BuildContext context) {
    final m = message;
    final colors = Theme.of(context).colorScheme;
    final bubbleColor =
        isOwnMessage ? colors.primaryContainer : colors.surfaceContainerHigh;
    final textColor =
        isOwnMessage ? colors.onPrimaryContainer : colors.onSurface;
    final hasAvatarColumn = showsAvatarColumn(
        isOwnMessage: isOwnMessage, isDirectMessage: isDirectMessage);
    final hasName = showsName(
        isOwnMessage: isOwnMessage,
        isDirectMessage: isDirectMessage,
        showSender: m.showSender);
    final side =
        isOwnMessage ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    // The short time, also while the list layout would show the detailed one
    // on hover, so a bubble keeps its size.
    final time = m.layoutTimestamp ?? m.timestamp;

    return LayoutBuilder(builder: (context, constraints) {
      final footer = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (m.edited) ...[
            tiamat.Text.labelLow(m.messageEditedMarker),
            const SizedBox(width: 4),
          ],
          if (time != null) tiamat.Text.labelLow(time, maxLines: 1),
          if (m.sharedBy != null) m.sharedMark(context),
          if (m.timestampMark != null) m.timestampMark!,
        ],
      );

      final bubble = Container(
        constraints:
            BoxConstraints(maxWidth: constraints.maxWidth * maxWidthFraction),
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.circular(12),
          border: m.isMentioningSelf
              ? Border.all(color: colors.tertiary, width: 2)
              : null,
        ),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: textColor),
          child: GestureDetector(
            onDoubleTap: m.onDoubleTapMessage,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (m.inResponseTo != null) m.inResponseTo!,
                if (m.forwardedFrom != null) m.forwardedFrom!,
                if (m.formattedContent != null)
                  RepaintBoundary(child: m.formattedContent!),
                if (m.attachments != null) m.attachments!,
                if (m.sticker != null) m.sticker!,
                if (m.urlPreviews != null) m.urlPreviews!,
                Align(
                  alignment: Alignment.centerRight,
                  widthFactor: 1,
                  child: SelectionContainer.disabled(child: footer),
                ),
              ],
            ),
          ),
        ),
      );

      final column = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: side,
        children: [
          if (hasName)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 0, 2),
              child: m.name(RedactionScope.of(context)),
            ),
          bubble,
          if (m.reactions != null || m.readReceipts != null)
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (m.reactions != null)
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(0, 4, 0, 0),
                      child: m.reactions!,
                    ),
                  ),
                if (m.readReceipts != null)
                  SizedBox(width: 35, child: m.readReceipts),
              ],
            ),
        ],
      );

      return Padding(
        padding: EdgeInsets.fromLTRB(12, m.showSender ? 6 : 2, 12, 2),
        child: Column(
          crossAxisAlignment: side,
          children: [
            Row(
              mainAxisAlignment: isOwnMessage
                  ? MainAxisAlignment.end
                  : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasAvatarColumn) ...[
                  Padding(
                    padding: EdgeInsets.fromLTRB(0, hasName ? 18 : 0, 0, 0),
                    // avatar() draws an empty slot when showSender is off.
                    child: m.avatar(),
                  ),
                  const SizedBox(width: 8),
                ],
                Flexible(child: column),
              ],
            ),
            if (m.thread != null)
              Padding(
                padding: EdgeInsets.fromLTRB(
                    hasAvatarColumn ? m.avatarSize + 8 : 0, 4, 0, 4),
                child: m.thread!,
              ),
          ],
        ),
      );
    });
  }
}
