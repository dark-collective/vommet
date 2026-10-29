import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/client/attachment.dart';
import 'package:commet/client/timeline.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'dart:async';
import 'package:commet/client/timeline_events/timeline_event_feature_per_message_profile.dart';
import 'package:commet/client/timeline_events/timeline_event_feature_related.dart';
import 'package:commet/client/timeline_events/timeline_event_message.dart';
import 'package:commet/client/timeline_events/timeline_event_sticker.dart';
import 'package:commet/diagnostic/benchmark_values.dart';
import 'package:commet/ui/atoms/reply_quote.dart';
import 'package:commet/utils/bold_text.dart';
import 'package:commet/ui/molecules/timeline_events/message_translation_fold.dart';
import 'package:commet/utils/translation/reply_quote_translation.dart';
import 'package:commet/ui/atoms/redaction_scope.dart';
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

  /// Vommet: the quote shows a text message as last edited (Vommet issue
  /// 823), not its original body. Media keeps [TimelineEvent.plainTextBody],
  /// which hides spoilered captions.
  static String quotedText(TimelineEvent event, Timeline timeline) {
    if (event is TimelineEventMessage &&
        _TimelineEventViewReplyState.mediaOf(event) == null) {
      return event.getPlaintextBody(timeline);
    }
    return event.plainTextBody;
  }

  /// Vommet: whether "Translate this room" translates a quote of [event]
  /// showing [text]: other people's text messages are, own messages, media
  /// and code are quoted as they are. The message box's reply strip uses it
  /// too.
  static bool translatesQuote(TimelineEvent event, String text, String? self) =>
      event is TimelineEventMessage &&
      _TimelineEventViewReplyState.mediaOf(event) == null &&
      event.senderId != self &&
      !_TimelineEventViewReplyState.quotesCode(event, text);
}

class _TimelineEventViewReplyState extends State<TimelineEventViewReply> {
  String? senderName;
  String? senderId;
  String? body;
  Color? senderColor;

  bool loading = false;
  String? replyEventId;

  /// Vommet: the quoted message's media kind, for the quote/card styles.
  ReplyQuoteMedia? media;

  /// Vommet: "Translate this room" translates the quote too.
  final ReplyQuoteTranslation translation = ReplyQuoteTranslation();

  @override
  void initState() {
    getStateFromIndex(widget.index);
    // Vommet issue 306: follow the quoted message, so deleting it shows
    // "Message deleted" here at once instead of its old text.
    quotedChanged = widget.timeline.onChange.stream.listen(onTimelineChanged);
    translation.addListener(onTranslationChanged);
    super.initState();
  }

  StreamSubscription<int>? quotedChanged;

  void onTimelineChanged(int index) {
    if (!mounted || replyEventId == null) return;
    if (index < 0 || index >= widget.timeline.events.length) return;
    final event = widget.timeline.events[index];
    if (event.eventId == replyEventId) setStateFromEvent(event);
  }

  void onTranslationChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    quotedChanged?.cancel();
    translation.removeListener(onTranslationChanged);
    translation.dispose();
    super.dispose();
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
          _applyLatestEdit(value);
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
      senderId = sender.identifier;
      senderName = sender.displayName;
      senderColor = sender.defaultColor;
      body = TimelineEventViewReply.quotedText(event, widget.timeline);
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
    followTranslation(event);
  }

  /// Vommet: other people's text messages are translated like the message
  /// itself; own messages, media and code are quoted as they are.
  void followTranslation(TimelineEvent event) {
    final text = body;
    final roomId = widget.timeline.room.identifier;
    final self = widget.timeline.room.client.self?.identifier;
    if (text == null ||
        media != null ||
        !TimelineEventViewReply.translatesQuote(event, text, self)) {
      translation.clear();
      return;
    }
    final room = widget.timeline.room;
    translation.show(
        roomId: roomId,
        eventId: event.eventId,
        text: text,
        roomLanguage: () => roomReadingLanguage(room));
  }

  /// Code doesn't go through the room translation (as in the message).
  static bool quotesCode(TimelineEventMessage event, String text) {
    final html = event.formattedBody;
    return text.contains("```") ||
        (html != null && (html.contains("<pre") || html.contains("<code")));
  }

  /// Vommet: a message fetched by id isn't in the loaded timeline, so its
  /// edits aren't either; ask the server for the latest one.
  void _applyLatestEdit(TimelineEvent event) {
    if (event is! TimelineEventMessage || mediaOf(event) != null) return;
    event.getEditHistory(widget.timeline).then((versions) {
      if (!mounted || versions.length < 2) return;
      if (replyEventId != event.eventId) return;
      setState(() => body = versions.first.body);
      followTranslation(event);
    }).catchError((_) {});
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
    final redaction = RedactionScope.of(context);
    final id = senderId ?? senderName ?? "";
    final shownName =
        senderName == null ? null : redaction.name(senderName!, id);
    final shownColor =
        senderColor == null ? null : redaction.nameColor(senderColor!, id);
    final bodyColor = material.Theme.of(context).colorScheme.secondary;
    final translated = translation.translated;
    final shownBody = translated ?? body;
    // Vommet: the quote and card styles (Settings › Appearance › Replies).
    final style = ReplyStyle.current;
    if (style.inline) {
      return ReplyQuote(
        style: style,
        senderName: shownName,
        senderColor: shownColor,
        body: shownBody == null ? null : redaction.text(shownBody),
        media: media,
        translated: translated != null,
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
          mouseCursor: WidgetStateMouseCursor.clickable,
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
                          text: "${shownName ?? "Loading"} ",
                          style: withBoldText(
                              context,
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: tiamat.Text.adjustColor(
                                      context, shownColor ?? Colors.white)))),
                      if (translated != null)
                        const WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: Padding(
                              padding: EdgeInsets.only(right: 4),
                              child: ReplyQuoteTranslatedMark(),
                            )),
                      TextSpan(
                          text: shownBody == null
                              ? "Unknown"
                              : redaction.text(shownBody),
                          style: redaction.redactedTextStyle(
                              withBoldText(
                                  context,
                                  Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: bodyColor)),
                              bodyColor.withAlpha(90))),
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
