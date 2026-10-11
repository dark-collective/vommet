import 'dart:convert';
import 'dart:math';

import 'package:commet/client/attachment.dart';
import 'package:commet/utils/voice_message.dart';
import 'package:commet/client/matrix/components/threads/matrix_thread_timeline.dart';
import 'package:commet/client/matrix/extensions/matrix_event_extensions.dart';
import 'package:commet/client/matrix/forwarding/forward_content.dart';
import 'package:commet/client/matrix/forwarding/matrix_forwarding.dart';
import 'package:commet/client/matrix/matrix_mxc_file_provider.dart';
import 'package:commet/client/matrix/matrix_mxc_image_provider.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/client/matrix/matrix_room_permissions.dart';
import 'package:commet/client/matrix/matrix_timeline.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event_mixin_per_message_profile.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event_mixin_reactions.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event_mixin_related.dart';
import 'package:commet/client/timeline.dart';
import 'package:commet/client/timeline_events/timeline_event_feature_forwarded.dart';
import 'package:commet/client/timeline_events/timeline_event_message.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/ui/atoms/rich_text/matrix_html_parser.dart';
import 'package:commet/utils/image/decode_limits.dart';
import 'package:commet/utils/mime.dart';
import 'package:commet/utils/text_utils.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart' as matrix;

import 'package:html/parser.dart' as html_parser;

class MatrixTimelineEventMessage extends MatrixTimelineEvent
    with
        MatrixTimelineEventRelated,
        MatrixTimelineEventReactions,
        MatrixTimelineEventPerMessageProfile
    implements TimelineEventMessage, TimelineEventFeatureForwarded {
  MatrixTimelineEventMessage(super.event, {required super.client}) {
    rawEvent = event;
    if (MatrixForwarding.enabled) {
      var origin = ForwardContent.originOf(event.content);
      if (origin != null) {
        forwardedFrom = ForwardedFrom(
            senderId: origin.sender,
            roomId: origin.roomId,
            eventId: origin.eventId,
            originalTime: origin.originServerTs != null
                ? DateTime.fromMillisecondsSinceEpoch(origin.originServerTs!)
                : null);
      }
      // Show the original message rather than the "Forwarded from" fallback.
      event = MatrixForwarding.displayEventOf(event) ?? event;
    }
    attachments = _parseAnyAttachments();
  }

  /// The event as received; [event] shows a forward's original message.
  late final matrix.Event rawEvent;

  @override
  ForwardedFrom? forwardedFrom;

  @override
  String get source =>
      const JsonEncoder.withIndent('  ').convert(rawEvent.toJson());

  matrix.Client get mx => client.getMatrixClient();

  @override
  late List<Attachment>? attachments;

  @override
  bool get editable => true;

  @override
  String? get body => stripFallback(event.plaintextBody);

  String get formattedBody => event.formattedText != ""
      ? stripFallbackHtml(event.formattedText)
      : stripFallback(event.plaintextBody);

  @override
  String? get bodyFormat =>
      event.content.tryGet<String>("format") ??
      "chat.commet.custom.matrix_plain";

  @override
  String get plainTextBody => stripFallback(event.plaintextBody);

  String _getPlaintextBody({Timeline? timeline}) =>
      stripFallback(_getRawPlaintextBody(timeline: timeline),
          timeline: timeline);

  String _getFormattedBody({Timeline? timeline}) =>
      stripFallbackHtml(_getRawFormattedBody(timeline: timeline),
          timeline: timeline);

  String _getRawPlaintextBody({Timeline? timeline}) {
    var e = getDisplayEvent(timeline);

    if (["m.file", "m.image", "m.video", "m.audio"].contains(e.messageType)) {
      var file = e.content["file"] is Map<String, dynamic>
          ? e.content['file'] as Map<String, dynamic>
          : null;
      if (e.content.containsKey("url") == false &&
          (file?.containsKey("url") != true)) {
        return e.plaintextBody;
      }

      if (e.content.containsKey("filename")) {
        if (e.content["filename"] == e.plaintextBody) {
          return "";
        }

        return e.plaintextBody;
      } else {
        return "";
      }
    }

    return e.plaintextBody;
  }

  String _getRawFormattedBody({Timeline? timeline}) {
    var e = getDisplayEvent(timeline);

    if (["m.file", "m.image", "m.video", "m.audio"].contains(e.messageType)) {
      return e.formattedText;
    }

    if (e.formattedText == "") {
      return e.plaintextBody;
    }

    return e.formattedText;
  }

  @override
  String getPlaintextBody(Timeline timeline) {
    var displayEvent = getDisplayEvent(timeline);

    return stripFallback(displayEvent.plaintextBody, timeline: timeline);
  }

  @override
  Widget? buildFormattedContent({Timeline? timeline}) {
    final room = client.getRoom(event.roomId!)!;

    var displayEvent = getDisplayEvent(timeline);
    bool isFormatted = displayEvent.content.tryGet<String>("format") != null;

    var mentions = displayEvent.content.tryGetMap("m.mentions");

    if (mentions?.isNotEmpty == true) {
      isFormatted = true;
    }

    if (isFormatted) {
      bool mentionsRoom = mentions?["room"] == true &&
          MatrixRoomPermissions.canUserMentionRoom(
              displayEvent.senderId, (room as MatrixRoom).matrixRoom);

      return MatrixHtmlParser.parse(
          _getFormattedBody(timeline: timeline), client, room,
          mentionsRoom: mentionsRoom);
    } else {
      var plain = _getPlaintextBody(timeline: timeline);
      if (plain != "") {
        return PlaintextMessageBody(
          content: plain,
          clientIdentifier: client.identifier,
        );
      }
    }

    return null;
  }

  @override
  bool isEdited(Timeline timeline) {
    if (forwardedFrom != null) return false;
    var e = event.getDisplayEvent(getTimeline(timeline)!);
    return e.eventId != event.eventId;
  }

  List<Attachment>? _parseAnyAttachments() {
    String filename = event.content.containsKey("filename")
        ? event.content["filename"] as String
        : event.body;

    if (event.hasAttachment) {
      double? width = event.attachmentWidth;
      double? height = event.attachmentHeight;

      Attachment? attachment;

      if (Mime.imageTypes.contains(event.attachmentMimetype)) {
        attachment = ImageAttachment(
            MatrixMxcImage(event.attachmentMxcUrl!, mx,
                blurhash: event.attachmentBlurhash,
                doThumbnail: event.hasThumbnail,
                doFullres: true,
                thumbnailHeight: event.thumbnailHeight != null
                    ? min(700, event.thumbnailHeight!.toInt())
                    : 700,
                autoLoadFullRes: !event.hasThumbnail,
                matrixEvent: event)
              // I noticed on linux, decoding really high res images would cause a flicker, so we will limit it
              // Vommet: by pixel count and longest side, not by height:
              // a height cap squashed tall screenshots to a few px wide.
              ..fullResLimits = PlatformUtils.isLinux
                  ? ImageDecodeLimits.linuxTimeline
                  : null,
            MxcFileProvider(mx, event.attachmentMxcUrl!, event: event),
            mimeType: event.attachmentMimetype,
            width: width,
            fileSize: event.infoMap['size'] as int?,
            name: filename,
            height: height);
      } else if (Mime.videoTypes.contains(event.attachmentMimetype)) {
        // Only load videos if the event has finished sending, otherwise
        // matrix dart sdk gives us the video file when we ask for thumbnail
        if (event.status.isSending == false) {
          attachment = VideoAttachment(
              MxcFileProvider(mx, event.attachmentMxcUrl!, event: event),
              thumbnail: event.videoThumbnailUrl != null
                  ? MatrixMxcImage(event.videoThumbnailUrl!, mx,
                      blurhash: event.attachmentBlurhash,
                      doFullres: false,
                      autoLoadFullRes: false,
                      doThumbnail: true,
                      matrixEvent: event)
                  : null,
              name: filename,
              mimeType: event.attachmentMimetype,
              duration: event.attachmentDuration,
              width: width,
              fileSize: event.infoMap['size'] as int?,
              height: height);
        }
      } else if (event.messageType == "m.audio" ||
          event.attachmentMimetype.startsWith("audio/")) {
        final voice = VoiceMessage.parse(event.content);
        attachment = AudioAttachment(
            MxcFileProvider(mx, event.attachmentMxcUrl!, event: event),
            name: filename,
            mimeType: event.attachmentMimetype,
            fileSize: event.infoMap['size'] as int?,
            duration: voice?.duration ?? event.attachmentDuration,
            waveform: voice?.waveform,
            isVoice: voice?.isVoice ?? false);
      } else {
        attachment = FileAttachment(
            MxcFileProvider(mx, event.attachmentMxcUrl!, event: event),
            name: filename,
            mimeType: event.attachmentMimetype,
            fileSize: event.infoMap['size'] as int?);
      }

      return List.from([attachment]);
    }

    return null;
  }

  @override
  List<Uri>? getLinks({Timeline? timeline}) {
    var text = _getFormattedBody(timeline: timeline);
    var start = text.indexOf("<mx-reply>");
    var end = text.indexOf("</mx-reply>");

    if (start != -1 && end != -1 && start < end) {
      text = text.replaceRange(start, end, "");
    }

    var foundLinks = TextUtils.findUrls(text);

    foundLinks?.removeWhere((element) => element.authority == "matrix.to");
    if (foundLinks?.isEmpty == true) {
      foundLinks = null;
    }

    return foundLinks;
  }

  @override
  matrix.Event getPerMessageProfileSource({Timeline? timeline}) =>
      getDisplayEvent(timeline);

  matrix.Event getDisplayEvent(Timeline? tl) {
    // Forwards can't be edited (MSC4553).
    if (forwardedFrom != null) return event;

    var mx = getTimeline(tl);

    if (mx == null) return event;

    return event.getDisplayEvent(mx);
  }

  matrix.Timeline? getTimeline(Timeline? tl) {
    if (tl == null) return null;

    if (tl is MatrixThreadTimeline) {
      return tl.mainRoomTimeline.matrixTimeline;
    } else {
      return (tl as MatrixTimeline).matrixTimeline;
    }
  }
}

class PlaintextMessageBody extends StatelessWidget {
  const PlaintextMessageBody(
      {required this.content, required this.clientIdentifier, super.key});
  final String content;
  final String clientIdentifier;

  @override
  Widget build(BuildContext context) {
    var document = html_parser.parse(content);
    bool big = shouldDoBigEmoji(document);

    return Text.rich(TextSpan(
        style: TextStyle(fontSize: big ? 34 : null),
        children: TextUtils.linkifyString(content,
            context: context, clientId: clientIdentifier)));
  }
}
