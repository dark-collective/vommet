import 'dart:convert';
import 'dart:math';

import 'package:commet/ui/atoms/search_highlight.dart';
import 'package:commet/client/attachment.dart';
import 'package:commet/config/timeline_image_size.dart';
import 'package:commet/utils/voice_message.dart';
import 'package:commet/client/matrix/components/threads/matrix_thread_timeline.dart';
import 'package:commet/client/matrix/extensions/matrix_event_extensions.dart';
import 'package:commet/client/matrix/forwarding/forward_content.dart';
import 'package:commet/client/matrix/forwarding/matrix_forwarding.dart';
import 'package:commet/client/matrix/matrix_mxc_file_provider.dart';
import 'package:commet/client/matrix/matrix_mxc_image_provider.dart';
import 'package:commet/client/matrix/matrix_room.dart';
// Vommet
import 'package:commet/utils/attachment_mime.dart';
import 'package:commet/utils/media_spoiler.dart';
import 'package:commet/client/matrix/matrix_room_permissions.dart';
import 'package:commet/client/matrix/matrix_timeline.dart';
import 'package:commet/client/matrix/timeline_events/matrix_plaintext_cache.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event_mixin_per_message_profile.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event_mixin_reactions.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event_mixin_related.dart';
import 'package:commet/client/timeline.dart';
import 'package:commet/client/timeline_events/timeline_event_feature_forwarded.dart';
import 'package:commet/client/timeline_events/timeline_event_message.dart';
import 'package:commet/ui/atoms/rich_text/matrix_html_parser.dart';
import 'package:commet/utils/image/decode_limits.dart';
import 'package:commet/utils/image/lod_image.dart';
import 'package:commet/utils/mime.dart';
import 'package:commet/utils/text_utils.dart';
import 'package:flutter/material.dart';
import 'package:html_unescape/html_unescape.dart';
import 'package:matrix/matrix.dart' as matrix;

import 'package:html/parser.dart' as html_parser;
import 'package:commet/utils/gif_video.dart';

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
  String? get body => stripFallback(_eventPlaintextBody);

  String get formattedBody => event.formattedText != ""
      ? stripFallbackHtml(event.formattedText)
      : stripFallback(_eventPlaintextBody);

  static const _mediaTypes = ["m.file", "m.image", "m.video", "m.audio"];

  // Vommet: media with an empty or missing body reads as its filename, like
  // media sent normally, instead of the SDK's "Unknown message format".
  static bool _isMediaWithoutBody(matrix.Event e) =>
      _mediaTypes.contains(e.messageType) &&
      (e.content.tryGet<String>("body") ?? "").isEmpty &&
      e.formattedText.isEmpty;

  static String _plaintextOf(matrix.Event e) => _isMediaWithoutBody(e)
      ? e.content.tryGet<String>("filename") ?? ""
      : e.cachedPlaintextBody;

  String get _eventPlaintextBody => _plaintextOf(event);

  @override
  String? get bodyFormat =>
      event.content.tryGet<String>("format") ??
      "chat.commet.custom.matrix_plain";

  // Vommet: spoilered media (MSC4193) reads as "Image (spoiler)" in reply
  // previews, the room list and notifications, never as its file name.
  @override
  String get plainTextBody {
    final spoiler = _spoileredMedia;
    if (spoiler != null) {
      return MediaSpoiler.previewText(
          isVideo: spoiler is VideoAttachment, caption: _getPlaintextBody());
    }
    return stripFallback(_eventPlaintextBody);
  }

  /// Vommet: the spoilered picture or video of this message, if any.
  FileAttachment? get _spoileredMedia {
    for (final a in attachments ?? const <Attachment>[]) {
      if (a is FileAttachment &&
          a.spoiler != null &&
          (a is ImageAttachment || a is VideoAttachment)) {
        return a;
      }
    }
    return null;
  }

  String _getPlaintextBody({Timeline? timeline}) =>
      stripFallback(_getRawPlaintextBody(timeline: timeline),
          timeline: timeline);

  String _getFormattedBody({Timeline? timeline}) =>
      stripFallbackHtml(_getRawFormattedBody(timeline: timeline),
          timeline: timeline);

  String _getRawPlaintextBody({Timeline? timeline}) {
    var e = getDisplayEvent(timeline);

    if (_mediaTypes.contains(e.messageType)) {
      var file = e.content["file"] is Map<String, dynamic>
          ? e.content['file'] as Map<String, dynamic>
          : null;
      if (e.content.containsKey("url") == false &&
          (file?.containsKey("url") != true)) {
        return e.plaintextBody;
      }

      // Vommet: media without a body has no caption.
      if (_isMediaWithoutBody(e)) return "";

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

    return stripFallback(_plaintextOf(displayEvent), timeline: timeline);
  }

  /// Whether the message body renders from its HTML. Vommet: media whose
  /// formatted body is empty keeps its plain caption, even when `m.mentions`
  /// is set, as bridged replies do (Vommet issue 530).
  static bool usesFormattedBody(
      String messageType, Map<String, dynamic> content, String formattedText) {
    if (["m.file", "m.image", "m.video", "m.audio"].contains(messageType) &&
        formattedText.isEmpty) {
      return false;
    }

    if (content.tryGet<String>("format") != null) return true;

    return content.tryGetMap("m.mentions")?.isNotEmpty == true;
  }

  @override
  Widget? buildFormattedContent({Timeline? timeline}) {
    final room = client.getRoom(event.roomId!)!;

    var displayEvent = getDisplayEvent(timeline);
    var mentions = displayEvent.content.tryGetMap("m.mentions");

    if (usesFormattedBody(displayEvent.messageType, displayEvent.content,
        displayEvent.formattedText)) {
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

      // Vommet: by mimetype, falling back to the file extension when it is
      // missing or generic (pictures sent as m.file).
      final mimetype = AttachmentMime.ofEvent(event);

      // Vommet: AVIF and HEIC can't be decoded; show the sender's
      // thumbnail instead of the full picture (Vommet issue 329).
      final thumbnailOnly = AttachmentMime.showsThumbnailOnlyEvent(event);

      if (Mime.imageTypes.contains(mimetype) || thumbnailOnly) {
        attachment = ImageAttachment(
            MatrixMxcImage(event.attachmentMxcUrl!, mx,
                blurhash: event.attachmentBlurhash,
                doThumbnail: event.hasThumbnail,
                doFullres: !thumbnailOnly,
                thumbnailHeight: event.thumbnailHeight != null
                    ? min(700, event.thumbnailHeight!.toInt())
                    : 700,
                autoLoadFullRes: !event.hasThumbnail,
                // Vommet: the sender's thumbnail was all the timeline ever
                // showed, blurry when it is smaller than the tile (Vommet
                // issue 445). Use a cached full image, and load it when the
                // thumbnail is too small (auto-download still applies).
                useCachedFullRes: true,
                thumbnailTooSmall: (thumbnailWidth, _) =>
                    LODImageProvider.thumbnailTooSmallForTimeline(
                        thumbnailWidth,
                        fullWidth: width,
                        // Vommet issue 721: Large pictures need more pixels.
                        shownWidth: timelineImageSize.sharpWidth),
                matrixEvent: event,
                // Vommet: Media-tab tiles of unencrypted pictures use the
                // server's thumbnail of the original, not the original.
                tileEvent:
                    thumbnailOnly || event.isAttachmentEncrypted ? null : event)
              // I noticed on linux, decoding really high res images would cause a flicker, so we will limit it
              // Vommet: by pixel count and longest side, not by height:
              // a height cap squashed tall screenshots to a few px wide.
              // On every platform since Vommet issue 445: Android decoded
              // full images uncapped (a 12 MP photo is ~48 MB); the viewer
              // still decodes its own bigger copy (forViewer).
              ..fullResLimits = ImageDecodeLimits.linuxTimeline,
            MxcFileProvider(mx, event.attachmentMxcUrl!, event: event),
            mimeType: mimetype,
            width: width,
            fileSize: event.infoMap['size'] as int?,
            name: filename,
            height: height);
      } else if (Mime.videoTypes.contains(mimetype)) {
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
              isGif: isGifVideoInfo(event.infoMap),
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

      // Vommet: MSC4193 media spoilers, pictures and videos only (pictures
      // sent as m.file included, they are ImageAttachments above).
      if (attachment is ImageAttachment || attachment is VideoAttachment) {
        (attachment as FileAttachment).spoiler =
            MediaSpoiler.parse(event.content, key: rawEvent.eventId);
      }

      return List.from([attachment]);
    }

    return null;
  }

  @override
  List<Uri>? getLinks({Timeline? timeline}) =>
      findLinks(_getFormattedBody(timeline: timeline));

  /// The links in a message's formatted (or plain) body, without the reply
  /// fallback and matrix.to links.
  static List<Uri>? findLinks(String body) {
    var text = body;
    var start = text.indexOf("<mx-reply>");
    var end = text.indexOf("</mx-reply>");

    if (start != -1 && end != -1 && start < end) {
      text = text.replaceRange(start, end, "");
    }

    // Vommet issue 352: look for links in the decoded text. In the raw HTML
    // "<https://x>" is "&lt;https://x&gt;" and gave "https://x&gt", and
    // "?a=1&amp;b=2" cut the link short at "&amp".
    text = HtmlUnescape().convert(text);

    var foundLinks = TextUtils.findUrls(text)?.toSet().toList();

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

    var spans = TextUtils.linkifyString(content,
        context: context, clientId: clientIdentifier);
    // Vommet issue 611: the in-chat search's words.
    final words = SearchHighlightScope.wordsOf(context);
    if (words.isNotEmpty) {
      spans = SearchHighlightScope.highlightSpans(
          spans, words, SearchHighlightScope.styleOf(context));
    }

    return Text.rich(
        TextSpan(style: TextStyle(fontSize: big ? 34 : null), children: spans));
  }
}
