import 'package:commet/diagnostic/benchmark_values.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class TimelineEventLayoutMessage extends StatelessWidget {
  const TimelineEventLayoutMessage(
      {super.key,
      required this.senderName,
      required this.senderColor,
      this.viaSenderName,
      this.senderAvatar,
      this.formattedContent,
      this.forwardedFrom,
      this.attachments,
      this.inResponseTo,
      this.reactions,
      this.timestamp,
      this.sticker,
      this.thread,
      this.urlPreviews,
      this.readReceipts,
      this.onAvatarTapped,
      this.edited = false,
      this.sharedBy,
      this.isMentioningSelf = false,
      this.avatarSize = 32,
      this.avatarBuilder,
      this.showSender = true,
      this.onDoubleTapMessage});
  final String senderName;
  final Color senderColor;
  final String? viaSenderName;
  final ImageProvider? senderAvatar;
  final Widget? formattedContent;

  /// Vommet: "Forwarded from" header of a forwarded message.
  final Widget? forwardedFrom;
  final Widget? attachments;
  final Widget? inResponseTo;
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
  final bool isMentioningSelf;
  final String? timestamp;
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
          if (inResponseTo != null) inResponseTo!,
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
                      if (showSender)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(child: name()),
                            if (timestamp != null)
                              Row(mainAxisSize: MainAxisSize.min, children: [
                                tiamat.Text.labelLow(timestamp!),
                                if (sharedBy != null) sharedMark(context),
                              ]),
                          ],
                        ),
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

  Widget name() {
    Widget result = MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onAvatarTapped,
        child: tiamat.Text.name(
          senderName,
          color: senderColor,
        ),
      ),
    );

    if (viaSenderName != null) {
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
