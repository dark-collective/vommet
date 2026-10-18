import 'dart:math' as math;

import 'package:commet/cache/file_provider.dart';
import 'package:commet/client/attachment.dart';
import 'package:commet/client/components/url_preview/url_preview_component.dart';
import 'package:commet/client/components/url_preview/url_preview_suppression.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_mxc_image_provider.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event_message.dart';
import 'package:commet/client/room.dart';
import 'package:commet/client/timeline.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/client/timeline_events/timeline_event_message.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/utils/mime.dart';
import 'package:flutter/widgets.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:matrix/matrix_api_lite.dart';

class MatrixUrlPreviewComponent implements UrlPreviewComponent<MatrixClient> {
  @override
  MatrixClient client;

  MatrixUrlPreviewComponent(this.client);

  Map<String, UrlPreviewData> cache = {};

  bool? serverSupportsUrlPreview;

  @override
  Future<UrlPreviewData?> getPreview(
      Timeline timeline, TimelineEvent event) async {
    if (event is! TimelineEventMessage) {
      return null;
    }

    final room = timeline.room;

    if (room.isE2EE && preferences.urlPreviewInE2EEChat.value == false) {
      Log.i(
          "Not getting url preview because chat is encrypted and its not enabled");
      return null;
    }

    var mxClient = (room as MatrixRoom).matrixRoom.client;

    var uri = previewLinks(timeline, event).first;

    if (cache.containsKey(uri.toString())) {
      return cache[uri.toString()];
    }

    UrlPreviewData? data;

    try {
      data = await fetchPreviewData(mxClient, uri);
    } catch (_) {
      return null;
    }

    if (data != null) {
      cache[uri.toString()] = data;
    } else {
      cache[uri.toString()] = UrlPreviewComponent.invalidPreviewData;
    }

    return data;
  }

  @override
  UrlPreviewData? getCachedPreview(Timeline timeline, TimelineEvent event) {
    if (event is! TimelineEventMessage) {
      return null;
    }

    var uri = previewLinks(timeline, event).firstOrNull;

    if (uri == null) {
      return null;
    }

    if (cache.containsKey(uri.toString())) {
      return cache[uri.toString()];
    }

    return null;
  }

  @override
  bool shouldGetPreviewsInRoom(Room room) {
    if (room.isE2EE && preferences.urlPreviewInE2EEChat.value == false) {
      return false;
    }

    if (serverSupportsUrlPreview == false) {
      return false;
    }

    return true;
  }

  @override
  bool shouldGetPreviewDataForTimelineEvent(
      Timeline timeline, TimelineEvent event) {
    if (event is! TimelineEventMessage) {
      return false;
    }

    final room = timeline.room;

    if (!shouldGetPreviewsInRoom(room)) {
      return false;
    }

    return previewLinks(timeline, event).isNotEmpty;
  }

  /// The message's links that may get a preview: not the ones written as
  /// `<url>` in its body, and only those its MSC4095 list names, if it has
  /// one (Vommet issue 352).
  static List<Uri> previewLinks(Timeline timeline, TimelineEventMessage event) {
    final links = event.getLinks(timeline: timeline);
    if (links == null) return const [];

    final content = event is MatrixTimelineEventMessage
        ? event.getDisplayEvent(timeline).content
        : null;

    return UrlPreviewSuppression(event.getPlaintextBody(timeline),
            content: content)
        .filter(links);
  }

  Future<String> getRequestPath() async {
    if (await client.getMatrixClient().authenticatedMediaSupported()) {
      return '/client/v1/media/preview_url';
    } else {
      return '/media/v3/preview_url';
    }
  }

  @override
  Future<UrlPreviewData?> getPreviewForUrl(Room room, Uri uri) async {
    if (shouldGetPreviewsInRoom(room) == false) {
      return null;
    }

    if (uri.authority == "matrix.to") {
      return null;
    }

    if (cache.containsKey(uri.toString())) {
      return cache[uri.toString()];
    }

    var data = null;

    try {
      data =
          await fetchPreviewData((room as MatrixRoom).matrixRoom.client, uri);
    } catch (_) {
      return null;
    }

    if (data != null) {
      cache[uri.toString()] = data;
    }

    return data;
  }

  Future<UrlPreviewData?> fetchPreviewData(
      matrix.Client client, Uri url) async {
    late Map<String, Object?> response;
    try {
      response = await client.request(
          matrix.RequestType.GET, await getRequestPath(),
          query: {"url": url.toString()});
    } catch (e, s) {
      if (e is MatrixException) {
        if (e.error == MatrixError.M_UNRECOGNIZED) {
          serverSupportsUrlPreview = false;
        }
      }

      Log.onError(e, s);

      return null;
    }

    serverSupportsUrlPreview = true;
    // Vommet: homeservers disagree on the types of Open Graph fields. Synapse
    // sends every og:* value as a string; Tuwunel sends numbers (og:image:width,
    // og:video:width, ...) as JSON numbers. A plain `as String?` cast threw on
    // those, the exception was swallowed, and the preview card stayed on its
    // loading shimmer forever (every YouTube link, for example). Read each
    // field by what it is, not by what one server happens to send.
    var title = ogString(response['og:title']);
    var siteName = ogString(response['og:site_name']);
    var imageUrl = ogString(response['og:image']);
    var description = ogString(response['og:description']);
    var video =
        ogString(response['og:video:secure_url'] ?? response["og:video"]);
    var videoType = ogString(response['og:video:type']);

    var videoWidth = ogInt(response['og:video:width']);
    var videoHeight = ogInt(response['og:video:height']);
    if (videoWidth == null || videoHeight == null) {
      videoWidth = null;
      videoHeight = null;
    }

    var type = ogString(response["og:image:type"]);
    if (type != null) {
      if (Mime.displayableImageTypes.contains(type) == false) {
        imageUrl = null;
      }
    }

    // Vommet issue 336: the preview image is whatever the linked page names,
    // so it can be huge (a 250 MB animated PNG crashed the app). Skip it when
    // the server says it is too big, and cap the size it is decoded at.
    final imageDecodeHeight = previewImageDecodeHeight(
        bytes: ogInt(response['matrix:image:size']),
        width: ogInt(response['og:image:width']),
        height: ogInt(response['og:image:height']));
    if (imageDecodeHeight == null) {
      imageUrl = null;
    }

    ImageProvider? image;
    if (imageUrl != null) {
      var imageUri = Uri.parse(imageUrl);
      if (imageUri.scheme == "mxc") {
        try {
          image = MatrixMxcImage(imageUri, client,
              doThumbnail: false, fullResHeight: imageDecodeHeight);
        } catch (exception, stack) {
          Log.onError(exception, stack);
          Log.w("Failed to get mxc image");
        }
      }
    }

    var destinationType = UrlDestinationType.page;
    VideoAttachment? videoAttachment;

    if (video != null) {
      destinationType = UrlDestinationType.video;
    }

    if (video is String &&
        videoType != null &&
        (Mime.videoTypes.contains(videoType) ||
            Mime.videoStreamTypes.contains(videoType))) {
      var uri = Uri.parse(video);

      if (uri.scheme == "https") {
        videoAttachment = VideoAttachment(WebFileProvider(uri),
            width: videoWidth?.toDouble(),
            height: videoHeight?.toDouble(),
            streamUrl: uri,
            thumbnail: image,
            mimeType: videoType);
      }
    }

    if (description != null) {
      description = description.replaceAll("\n", "    ");
    }

    return UrlPreviewData(url,
        siteName: siteName,
        title: title,
        image: image,
        video: videoAttachment,
        type: destinationType,
        description: description);
  }

  /// An Open Graph value as text, whatever JSON type the server used.
  static String? ogString(Object? value) {
    if (value == null) return null;
    if (value is String) return value;
    if (value is num || value is bool) return value.toString();
    return null;
  }

  /// Vommet issue 336: largest preview image downloaded, by the
  /// `matrix:image:size` the server reports.
  static const maxPreviewImageBytes = 10 * 1024 * 1024;

  /// Preview images with more pixels than this are skipped.
  static const maxPreviewImagePixels = 8192 * 8192;

  /// Longest side a preview image is decoded at (the card is 300 px wide;
  /// tapping it opens the same image in the viewer).
  static const maxPreviewImageSide = 2048;

  /// Decode height when the server doesn't report the image's dimensions.
  static const unknownPreviewImageHeight = 1024;

  /// The height to decode a preview image at, or null to leave it out.
  /// [bytes], [width] and [height] are what the server measured when it
  /// fetched the image (`matrix:image:size`, `og:image:width/height`).
  static int? previewImageDecodeHeight({int? bytes, int? width, int? height}) {
    if (bytes != null && bytes > maxPreviewImageBytes) return null;

    if (width == null || height == null || width <= 0 || height <= 0) {
      return unknownPreviewImageHeight;
    }

    if (width * height > maxPreviewImagePixels) return null;

    final longest = math.max(width, height);
    if (longest <= maxPreviewImageSide) return height;
    return math.max(1, height * maxPreviewImageSide ~/ longest);
  }

  /// An Open Graph value as an integer: JSON numbers, or digits in a string.
  static int? ogInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }
}
