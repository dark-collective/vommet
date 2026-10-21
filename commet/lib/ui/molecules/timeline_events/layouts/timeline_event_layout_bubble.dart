import 'package:commet/config/message_density.dart';
import 'package:commet/ui/atoms/redaction_scope.dart';
import 'package:commet/ui/molecules/timeline_events/layouts/timeline_event_layout_message.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/config/style/theme_extensions.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet: chat-bubble layout for a message (Vommet issue 421), opt-in via
/// `preferences.chatBubbleLayout`. Your own messages sit on the right,
/// everyone else's on the left; on a wide timeline (at least
/// [allLeftMinWidth]) all of them sit on the left, yours with your avatar and
/// name like everyone else's (Vommet issue 507). It draws the parts of [message] (the list
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

  /// From this timeline width on, every bubble sits on the left, so your eyes
  /// don't jump across a wide window (Vommet issue 507).
  static const double allLeftMinWidth = 1000;

  /// Whether your own bubble goes on the right in a timeline [width] wide.
  static bool ownOnRight({required bool isOwnMessage, required double width}) =>
      isOwnMessage && width < allLeftMinWidth;

  /// Avatars (and the space they take) only in group rooms, and on your own
  /// messages only while they share the left side.
  static bool showsAvatarColumn(
          {required bool isOwnMessage,
          required bool isDirectMessage,
          required double width}) =>
      !isDirectMessage && !ownOnRight(isOwnMessage: isOwnMessage, width: width);

  /// The name and avatar go on the first bubble of a run, in group rooms
  /// only, and not on your own bubbles while they sit on the right.
  static bool showsName(
          {required bool isOwnMessage,
          required bool isDirectMessage,
          required bool showSender,
          required double width}) =>
      showSender &&
      showsAvatarColumn(
          isOwnMessage: isOwnMessage,
          isDirectMessage: isDirectMessage,
          width: width);

  /// The bubble colour and its text colour. Your own bubbles use the
  /// theme's primary container, unless the message text (drawn in
  /// `onSurface`) can't be read on it: AMOLED sets no container colours, so
  /// its primary container is plain white under white text (Vommet issue
  /// 502). Those themes get a shade blended from the primary colour.
  /// A colour the theme picked ([ExtraColors.ownBubble] / `otherBubble`,
  /// Vommet issue 532) is used as it is, with whichever of the text and
  /// accent-text colours reads better on it.
  static (Color, Color) bubbleColors(ColorScheme colors,
      {required bool isOwnMessage, ExtraColors? extra}) {
    final picked = isOwnMessage ? extra?.ownBubble : extra?.otherBubble;
    if (picked != null) {
      final solid = Color.alphaBlend(picked, colors.surface);
      final text = contrastRatio(solid, colors.onSurface) >=
              contrastRatio(solid, colors.onPrimary)
          ? colors.onSurface
          : colors.onPrimary;
      return (picked, text);
    }
    if (!isOwnMessage) return (colors.surfaceContainerHigh, colors.onSurface);
    if (contrastRatio(colors.primaryContainer, colors.onSurface) >= 3) {
      return (colors.primaryContainer, colors.onPrimaryContainer);
    }
    return (
      Color.alphaBlend(colors.primary.withValues(alpha: 0.2), colors.surface),
      colors.onSurface
    );
  }

  /// WCAG contrast ratio of two opaque colours, 1 (same) to 21.
  static double contrastRatio(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    return la > lb ? (la + 0.05) / (lb + 0.05) : (lb + 0.05) / (la + 0.05);
  }

  @override
  Widget build(BuildContext context) {
    final m = message;
    final density = messageDensity;
    final colors = Theme.of(context).colorScheme;
    final (bubbleColor, textColor) = bubbleColors(colors,
        isOwnMessage: isOwnMessage,
        extra: Theme.of(context).extension<ExtraColors>());
    // The short time, also while the list layout would show the detailed one
    // on hover, so a bubble keeps its size.
    final time = m.layoutTimestamp ?? m.timestamp;

    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      final onRight = ownOnRight(isOwnMessage: isOwnMessage, width: width);
      final hasAvatarColumn = showsAvatarColumn(
          isOwnMessage: isOwnMessage,
          isDirectMessage: isDirectMessage,
          width: width);
      final hasName = showsName(
          isOwnMessage: isOwnMessage,
          isDirectMessage: isDirectMessage,
          showSender: m.showSender,
          width: width);
      final side = onRight ? CrossAxisAlignment.end : CrossAxisAlignment.start;
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
        constraints: BoxConstraints(maxWidth: width * maxWidthFraction),
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
        // Vommet: Settings › Appearance › Message spacing.
        padding: EdgeInsets.fromLTRB(
            12,
            m.showSender ? density.groupGap : density.verticalPadding,
            12,
            density.verticalPadding),
        child: Column(
          crossAxisAlignment: side,
          children: [
            Row(
              mainAxisAlignment:
                  onRight ? MainAxisAlignment.end : MainAxisAlignment.start,
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
