import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/client/attachment.dart';
import 'package:commet/client/timeline.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/client/timeline_events/timeline_event_feature_per_message_profile.dart';
import 'package:commet/client/timeline_events/timeline_event_feature_related.dart';
import 'package:commet/client/timeline_events/timeline_event_message.dart';
import 'package:commet/client/timeline_events/timeline_event_sticker.dart';
import 'package:commet/diagnostic/benchmark_values.dart';
import 'package:commet/ui/atoms/reply_quote.dart';
import 'package:commet/utils/bold_text.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:flutter/material.dart' as material;

class TimelineEventViewReply extends StatefulWidget {
  const TimelineEventViewReply(
      {super.key,
      required this.timeline,
      required this.index,
      this.jumpToEvent,
      this.avatarSize = 32});
  final Timeline timeline;
  final Function(String eventId)? jumpToEvent;
  final int index;
  final double avatarSize;

  @override
  State<TimelineEventViewReply> createState() => _TimelineEventViewReplyState();
}

class _TimelineEventViewReplyState extends State<TimelineEventViewReply> {
  String? senderName;
  String? body;
  Color? senderColor;

  bool loading = false;
  String? replyEventId;

  /// Vommet: the quoted message's media kind, for the quote/card styles.
  ReplyQuoteMedia? media;

  @override
  void initState() {
    getStateFromIndex(widget.index);
    super.initState();
  }

  void getStateFromIndex(int index) {
    var event = widget.timeline.events[index];
    if (event is! TimelineEventFeatureRelated) {
      return;
    }

    var e = event as TimelineEventFeatureRelated;
    if (e.relatedEventId == null) {
      return;
    }

    var replyEvent = widget.timeline.tryGetEvent(e.relatedEventId!);

    if (replyEvent == null) {
      loading = true;
      // Vommet: reply previews look up through getReplyEvent, which counts
      // the outcome for the opt-in "reply_lookup" diagnostics.
      final room = widget.timeline.room;
      (room is MatrixRoom
              ? room.getReplyEvent(e.relatedEventId!)
              : room.getEvent(e.relatedEventId!))
          .then((value) {
        if (mounted && value != null) {
          setStateFromEvent(value);
        }
      });
    } else {
      setStateFromEvent(replyEvent);
    }
  }

  void setStateFromEvent(TimelineEvent event) {
    setState(() {
      replyEventId = event.eventId;
      var sender = widget.timeline.room.getMemberOrFallback(event.senderId);
      senderName = sender.displayName;
      senderColor = sender.defaultColor;
      body = event.plainTextBody;
      media = mediaOf(event);
      loading = false;

      if (event is TimelineEventFeaturePerMessageProfile) {
        var profile = (event as TimelineEventFeaturePerMessageProfile)
            .getPerMessageProfile(timeline: widget.timeline);

        if (profile?.hasDisplayName == true) {
          senderName = profile!.displayName;
          senderColor = profile.color;
        }
      }
    });
  }

  /// Vommet: a picture's body is its file name; the quote shows the kind
  /// instead.
  static ReplyQuoteMedia? mediaOf(TimelineEvent event) {
    if (event is TimelineEventSticker) return ReplyQuoteMedia.sticker;
    if (event is! TimelineEventMessage) return null;
    final first = event.attachments?.firstOrNull;
    return switch (first) {
      null => null,
      ImageAttachment() => ReplyQuoteMedia.image,
      VideoAttachment() => ReplyQuoteMedia.video,
      AudioAttachment() => ReplyQuoteMedia.audio,
      _ => ReplyQuoteMedia.file,
    };
  }

  @override
  Widget build(BuildContext context) {
    BenchmarkValues.numTimelineReplyBodyBuilt += 1;
    // Vommet: the quote and card styles (Settings › Appearance › Replies).
    final style = ReplyStyle.current;
    if (style.inline) {
      return ReplyQuote(
        style: style,
        senderName: senderName,
        senderColor: senderColor,
        body: body,
        media: media,
        onTap: replyEventId == null
            ? null
            : () => widget.jumpToEvent?.call(replyEventId!),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => widget.jumpToEvent?.call(replyEventId!),
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: 45,
                child: SizedBox.expand(
                  child: CustomPaint(
                    painter: ReplyLinePainter2(
                        pathColor:
                            material.Theme.of(context).colorScheme.secondary,
                        avatarSize: widget.avatarSize),
                  ),
                ),
              ),
              Flexible(
                child: RichText(
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                    text: TextSpan(children: [
                      TextSpan(
                          text: "${senderName ?? "Loading"} ",
                          style: withBoldText(
                              context,
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: tiamat.Text.adjustColor(
                                      context, senderColor ?? Colors.white)))),
                      TextSpan(
                          text: body ?? "Unknown",
                          style: withBoldText(
                              context,
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: material.Theme.of(context)
                                      .colorScheme
                                      .secondary))),
                    ])),
              )
              // Column(
              //   children: [
              //     tiamat.Text(
              //       senderName ?? "Loading",
              //       color: senderColor,
              //       autoAdjustBrightness: true,
              //     ),
              //   ],
              // ),
              // Flexible(
              //   child: Padding(
              //     padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
              //     child: tiamat.Text(
              //       body ?? "Unknown",
              //       maxLines: 2,
              //       overflow: TextOverflow.ellipsis,
              //       color: material.Theme.of(context).colorScheme.secondary,
              //     ),
              //   ),
              // ),
            ]),
          ),
        ),
      ),
    );
  }
}

class ReplyLinePainter2 extends CustomPainter {
  Color pathColor;
  double strokeWidth;
  double radius;
  double padding;
  double avatarSize;
  ReplyLinePainter2(
      {this.pathColor = Colors.white,
      this.strokeWidth = 1.5,
      this.radius = 5,
      this.avatarSize = 32,
      this.padding = 4}) {
    _paint = Paint()
      ..color = pathColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
  }

  late Paint _paint;

  @override
  void paint(Canvas canvas, Size size) {
    Path path = Path();
    path.moveTo(avatarSize / 2, size.height - padding);
    path.relativeLineTo(0, (-size.height + 9 + padding) + radius);
    path.relativeArcToPoint(Offset(radius, -radius),
        radius: Radius.circular(radius));
    path.relativeLineTo(size.width - (avatarSize / 2) - radius - padding, 0);
    canvas.drawPath(path, _paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    return true;
  }
}
