import 'package:commet/config/message_density.dart';
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
      this.nameTrailing,
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
      this.onEditedTapped,
      this.sharedBy,
      this.timestampMark,
      this.readNote,
      this.isMentioningSelf = false,
      double? avatarSize,
      this.avatarBuilder,
      this.showSender = true,
      bool? showAvatar,
      this.avatarAtBottom = false,
      this.captionBelow = false,
      this.maxContentWidth,
      this.onDoubleTapMessage})
      : _avatarSize = avatarSize,
        showAvatar = showAvatar ?? showSender;
  final String senderName;
  final Color senderColor;

  /// For redacted mode: tells senders apart. Falls back to [senderName].
  final String? senderId;
  final String? viaSenderName;

  /// Vommet (network marks): after the sender name, e.g. the network icon.
  /// Stays visible when the name is cut short; hidden while names are
  /// redacted.
  final Widget? nameTrailing;
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

  /// Vommet: whether this row draws the sender's picture (else an empty
  /// slot). The first row of a run, or with [avatarAtBottom] the last.
  final bool showAvatar;

  /// Vommet: Settings › Appearance › Layout › Avatar: the picture lines up
  /// with the bottom of the row, beside the last message of a run.
  final bool avatarAtBottom;

  /// Vommet: Layout › Captions: the text sent with a picture or video goes
  /// under it.
  final bool captionBelow;

  /// Vommet: Layout › Limit message width: the widest the message (name,
  /// time and body) gets.
  final double? maxContentWidth;
  final bool edited;

  /// Vommet: opens the edit history when the edited mark is tapped.
  final VoidCallback? onEditedTapped;

  /// Vommet: the edited mark, tappable when [onEditedTapped] is set.
  Widget editedMark() {
    final label = tiamat.Text.labelLow(messageEditedMarker);
    if (onEditedTapped == null) return label;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onEditedTapped, child: label),
    );
  }

  /// Vommet: who shared the key to this message in an invite's history
  /// bundle (MSC4268); shown as a mark next to the time.
  final String? sharedBy;

  /// Vommet: a mark after the time (the personal pin mark).
  final Widget? timestampMark;

  /// Vommet issue 947: which sessions can't read your message. [compact] is
  /// the chat bubble's time row.
  final Widget Function({required bool compact})? readNote;
  final bool isMentioningSelf;
  final String? timestamp;

  /// Vommet: the short time, set while [timestamp] shows the detailed one on
  /// hover. The header picks its layout from this one, so hovering never moves
  /// the time under the name (Vommet issue 471).
  final String? layoutTimestamp;
  final Function()? onAvatarTapped;
  final Widget Function(Widget child)? avatarBuilder;
  final Function()? onDoubleTapMessage;

  final double? _avatarSize;

  /// Vommet: unless given, the size Settings › Appearance › Message spacing
  /// picks.
  double get avatarSize => _avatarSize ?? messageDensity.avatarSize;

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
    // Vommet: Settings › Appearance › Message spacing.
    final density = messageDensity;

    Widget result = Padding(
      padding: EdgeInsets.fromLTRB(
          leftPadding, density.verticalPadding, 8, density.verticalPadding),
      child: Column(
        children: [
          if (inResponseTo != null && !inlineReply) inResponseTo!,
          Row(
            crossAxisAlignment: avatarAtBottom
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              avatar(),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 0, 0),
                  child: limitWidth(Column(
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
                                  ...body(),
                                  if (sticker != null) sticker!,
                                  if (urlPreviews != null) urlPreviews!,
                                  if (readNote != null)
                                    readNote!(compact: false),
                                  if (reactions != null)
                                    Padding(
                                      padding: EdgeInsets.fromLTRB(
                                          0, density.innerGap, 0, 0),
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
                  )),
                ),
              )
            ],
          ),
          // Vommet: the thread card lines up with the message text.
          if (thread != null)
            Padding(
              padding: EdgeInsets.fromLTRB(
                  avatarSize + 12, density.innerGap, 35, density.innerGap),
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

  /// Vommet: the text, the edited mark and the attachments, the text under
  /// the attachments with [captionBelow].
  /// The bubble layout puts the edited mark in its footer instead.
  List<Widget> body({bool withEditedMark = true}) {
    final text = [
      if (formattedContent != null) RepaintBoundary(child: formattedContent!),
      if (edited && withEditedMark) editedMark(),
    ];
    if (attachments == null) return text;
    return captionBelow ? [attachments!, ...text] : [...text, attachments!];
  }

  /// Vommet: [child] no wider than [maxContentWidth] (plus the read
  /// receipts' column).
  Widget limitWidth(Widget child) {
    if (maxContentWidth == null) return child;
    return Align(
      alignment: Alignment.topLeft,
      widthFactor: 1,
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxContentWidth! + 35),
        child: child,
      ),
    );
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

    if (nameTrailing != null && !redaction.redactsNames) {
      result = Row(
        mainAxisSize: MainAxisSize.min,
        children: [Flexible(child: result), nameTrailing!],
      );
    }

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
            isPadding: showAvatar == false,
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
