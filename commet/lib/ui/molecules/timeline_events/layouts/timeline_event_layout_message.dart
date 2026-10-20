import 'package:commet/diagnostic/benchmark_values.dart';
import 'package:commet/ui/atoms/redaction_scope.dart';
import 'package:commet/utils/redaction/redaction_policy.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class TimelineEventLayoutMessage extends StatelessWidget {
  const TimelineEventLayoutMessage(
      {super.key,
      required this.senderName,
      required this.senderColor,
      this.senderId,
      this.viaSenderName,
      this.senderAvatar,
      this.formattedContent,
      this.forwardedFrom,
      this.attachments,
      this.inResponseTo,
      this.inlineReply = false,
      this.reactions,
      this.timestamp,
      this.layoutTimestamp,
      this.sticker,
      this.thread,
      this.urlPreviews,
      this.readReceipts,
      this.onAvatarTapped,
      this.edited = false,
      this.sharedBy,
      this.timestampMark,
      this.isMentioningSelf = false,
      this.avatarSize = 32,
      this.avatarBuilder,
      this.showSender = true,
      this.onDoubleTapMessage});
  final String senderName;
  final Color senderColor;

  /// For redacted mode: tells senders apart. Falls back to [senderName].
  final String? senderId;
  final String? viaSenderName;
  final ImageProvider? senderAvatar;
  final Widget? formattedContent;

  /// Vommet: "Forwarded from" header of a forwarded message.
  final Widget? forwardedFrom;
  final Widget? attachments;
  final Widget? inResponseTo;

  /// Vommet: [inResponseTo] goes inside the message under the sender's name
  /// (the quote and card reply styles) instead of above the avatar.
  final bool inlineReply;
  final Widget? reactions;
  final Widget? urlPreviews;
  final Widget? thread;
  final Widget? sticker;
  final Widget? readReceipts;
  final bool showSender;
  final bool edited;

  /// Vommet: who shared the key to this message in an invite's history
  /// bundle (MSC4268); shown as a mark next to the time.
  final String? sharedBy;

  /// Vommet: a mark after the time (the personal pin mark).
  final Widget? timestampMark;
  final bool isMentioningSelf;
  final String? timestamp;

  /// Vommet: the short time, set while [timestamp] shows the detailed one on
  /// hover. The header picks its layout from this one, so hovering never moves
  /// the time under the name (Vommet issue 471).
  final String? layoutTimestamp;
  final Function()? onAvatarTapped;
  final Widget Function(Widget child)? avatarBuilder;
  final Function()? onDoubleTapMessage;

  final double avatarSize;

  String get messageEditedMarker => Intl.message("(Edited)",
      name: "messageEditedMarker",
      desc: "Short text to mark that a message has been edited");

  String messageSentViaProfile(String sender) => Intl.message("via $sender",
      name: "messageSentViaProfile",
      desc:
          "Shows the real name of the account which sent a message with a per message profile",
      args: [sender]);

  Widget sharedMark(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Tooltip(
          message: "Shared by $sharedBy",
          child: Icon(Icons.history,
              key: const ValueKey("message-shared-history-mark"),
              size: 14,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      );

  @override
  Widget build(BuildContext context) {
    BenchmarkValues.numTimelineMessageBodyBuilt += 1;

    const double mentionHighlightSize = 3;
    double leftPadding = isMentioningSelf ? 16 - mentionHighlightSize : 16;

    Widget result = Padding(
      padding: EdgeInsets.fromLTRB(leftPadding, 2, 8, 2),
      child: Column(
        children: [
          if (inResponseTo != null && !inlineReply) inResponseTo!,
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              avatar(),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 0, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (showSender) header(context),
                      if (inResponseTo != null && inlineReply) inResponseTo!,
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: GestureDetector(
                              onDoubleTap: onDoubleTapMessage,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (forwardedFrom != null) forwardedFrom!,
                                  if (formattedContent != null)
                                    RepaintBoundary(child: formattedContent!),
                                  if (edited)
                                    tiamat.Text.labelLow(messageEditedMarker),
                                  if (attachments != null) attachments!,
                                  if (sticker != null) sticker!,
                                  if (urlPreviews != null) urlPreviews!,
                                  if (reactions != null)
                                    Padding(
                                      padding:
                                          const EdgeInsets.fromLTRB(0, 4, 0, 0),
                                      child: reactions!,
                                    ),
                                ],
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 35,
                            child: readReceipts,
                          )
                        ],
                      )
                    ],
                  ),
                ),
              )
            ],
          ),
          // Vommet: the thread card lines up with the message text.
          if (thread != null)
            Padding(
              padding: EdgeInsets.fromLTRB(avatarSize + 12, 4, 35, 4),
              child: thread!,
            ),
        ],
      ),
    );

    if (isMentioningSelf)
      result = Container(
        decoration: BoxDecoration(
            border: Border(
                left: BorderSide(
                    color: Theme.of(context).colorScheme.tertiary,
                    width: mentionHighlightSize)),
            color:
                Theme.of(context).colorScheme.tertiaryContainer.withAlpha(30)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
          child: result,
        ),
      );

    return result;
  }

  // Narrowest the sender name may get beside the timestamp before the
  // timestamp moves under it (narrow panes such as the pinned messages panel)
  static const double minNameWidthBesideTimestamp = 96;
  static const double timestampGap = 8;

  // Vommet: the name stays on one line, so the header keeps its height when
  // the timestamp switches to the longer detailed format on hover (Vommet
  // issue 446), and moves the timestamp under the name when both don't fit.
  // The layout follows the short time; a detailed time that doesn't fit
  // beside the name is drawn over it instead (Vommet issue 471).
  Widget header(BuildContext context) {
    final redaction = RedactionScope.of(context);
    if (timestamp == null) return name(redaction);

    return LayoutBuilder(builder: (context, constraints) {
      final timestampWidth = measureTimestamp(context, timestamp!);
      final layoutWidth = layoutTimestamp == null
          ? timestampWidth
          : measureTimestamp(context, layoutTimestamp!);

      bool fitsBesideName(double width) =>
          constraints.maxWidth - width - timestampGap >=
          minNameWidthBesideTimestamp;

      final time = Row(mainAxisSize: MainAxisSize.min, children: [
        Flexible(
            child: tiamat.Text.labelLow(timestamp!,
                maxLines: 1, overflow: TextOverflow.ellipsis)),
        if (sharedBy != null) sharedMark(context),
        if (timestampMark != null) timestampMark!,
      ]);

      if (!fitsBesideName(layoutWidth)) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [name(redaction), time],
        );
      }

      if (fitsBesideName(timestampWidth)) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(child: name(redaction)),
            const SizedBox(width: timestampGap),
            time,
          ],
        );
      }

      return Stack(
        children: [
          Row(children: [
            Flexible(child: name(redaction)),
            SizedBox(width: timestampGap + layoutWidth),
          ]),
          Positioned(
            top: 0,
            bottom: 0,
            right: 0,
            child: Container(
              key: detailedTimestampOverlayKey,
              constraints: BoxConstraints(maxWidth: constraints.maxWidth),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(4),
              ),
              child: time,
            ),
          ),
        ],
      );
    });
  }

  static const detailedTimestampOverlayKey =
      ValueKey("detailedTimestampOverlay");

  double measureTimestamp(BuildContext context, String text) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: Theme.of(context).textTheme.bodyMedium!.copyWith(
              fontWeight: FontWeight.w400,
              fontSize: 12,
            ),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    var width = painter.width;
    painter.dispose();
    if (sharedBy != null) width += 18;
    return width;
  }

  Widget name(RedactionPolicy redaction) {
    final id = senderId ?? senderName;
    Widget result = MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onAvatarTapped,
        child: tiamat.Text.name(
          redaction.name(senderName, id),
          color: redaction.nameColor(senderColor, id),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );

    if (viaSenderName != null && !redaction.redactsNames) {
      result = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: result),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 0, 0),
            child: tiamat.Text.labelLow(messageSentViaProfile(viaSenderName!)),
          ),
        ],
      );
    }

    return SelectionContainer.disabled(child: result);
  }

  Widget avatar() {
    Widget result = SizedBox(
      width: avatarSize,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onAvatarTapped,
          child: tiamat.Avatar(
            radius: avatarSize / 2,
            image: senderAvatar,
            placeholderText: senderName,
            placeholderColor: senderColor,
            redactionKey: senderId ?? senderName,
            isPadding: showSender == false,
          ),
        ),
      ),
    );

    if (avatarBuilder != null) {
      result = avatarBuilder!.call(result);
    }

    return result;
  }
}
