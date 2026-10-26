import 'dart:math' as math;
import 'dart:typed_data';

import 'package:commet/cache/file_provider.dart';
import 'package:commet/client/attachment.dart';
import 'package:commet/client/components/url_preview/bundled_url_preview.dart';
import 'package:commet/client/components/url_preview/url_preview_component.dart';
import 'package:commet/client/components/url_preview/url_preview_room_policy.dart';
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
import 'package:commet/utils/image/lod_image.dart';
import 'package:commet/client/matrix/components/url_preview/matrix_room_url_previews.dart';
import 'package:commet/utils/mime.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart' as matrix;
import 'package:matrix/matrix_api_lite.dart';

class MatrixUrlPreviewComponent
    implements UrlPreviewComponent<MatrixClient>, BundledUrlPreviewConsent {
  @override
  MatrixClient client;

  MatrixUrlPreviewComponent(this.client) {
    client.matrixClient.onSync.stream.listen(_onSync);
  }

  Map<String, UrlPreviewData> cache = {};

  /// Vommet issue 676: bundled previews by event and link, never by link
  /// alone (two senders can bundle different previews for the same link).
  final Map<String, UrlPreviewData> bundledCache = {};

  /// Events whose consent card got "Not now".
  final Set<String> dismissedBundled = {};

  /// Chats allowed (true), refused (false) or reset (null) on this device,
  /// until the account data comes back from the server.
  final Map<String, bool?> localRoomConsent = {};

  /// The Always/Never lists as just saved, until the server echoes them.
  BundledPreviewPeople? _pendingPeople;

  final ValueNotifier<int> _consentChanges = ValueNotifier(0);

  @override
  Listenable get bundledConsentChanges => _consentChanges;

  bool? serverSupportsUrlPreview;

  @override
  Future<UrlPreviewData?> getPreview(
      Timeline timeline, TimelineEvent event) async {
    if (event is! TimelineEventMessage) {
      return null;
    }

    final room = timeline.room;
    final bundled = bundledPreviewFor(timeline, event);
    if (bundled != null && !homeserverFirstIn(room)) {
      return bundledPreviewData(timeline, event, bundled);
    }

    if (!urlPreviewsAllowedIn(room)) {
      Log.i("Not getting url preview because previews are off in this room");
      return null;
    }

    var mxClient = (room as MatrixRoom).matrixRoom.client;

    var uri = previewLinks(timeline, event).firstOrNull;
    if (uri == null) {
      return UrlPreviewComponent.invalidPreviewData;
    }

    // Vommet issue 676: in an unencrypted chat the homeserver's preview
    // wins; the one the sender bundled is only the fallback.
    if (bundled != null && serverSupportsUrlPreview == false) {
      return bundledPreviewData(timeline, event, bundled, fallback: true);
    }

    if (cache.containsKey(uri.toString())) {
      final cached = cache[uri.toString()];
      if (bundled != null && !isUsable(cached)) {
        return bundledPreviewData(timeline, event, bundled, fallback: true);
      }
      return cached;
    }

    UrlPreviewData? data;

    // Vommet issue 377: a failed fetch returns the invalid marker, not null.
    // The timeline treats null as "still loading" and kept the loading
    // placeholder up until the room was reopened and read the cache.
    try {
      data = await fetchPreviewData(mxClient, uri);
    } catch (e) {
      // Not cached: a network error may be transient, so reopening the room
      // tries again (as before). Not a crash either, so no Log.onError.
      Log.w("Url preview fetch failed: $e");
      if (bundled != null) {
        return bundledPreviewData(timeline, event, bundled, fallback: true);
      }
      return UrlPreviewComponent.invalidPreviewData;
    }

    data ??= UrlPreviewComponent.invalidPreviewData;
    cache[uri.toString()] = data;

    if (bundled != null && !isUsable(data)) {
      return bundledPreviewData(timeline, event, bundled, fallback: true);
    }

    return data;
  }

  /// Whether a homeserver preview has something to show.
  static bool isUsable(UrlPreviewData? data) =>
      data != null &&
      data != UrlPreviewComponent.invalidPreviewData &&
      (data.title != null ||
          data.description != null ||
          data.image != null ||
          data.video != null);

  /// Vommet issue 676: whether [room] asks the homeserver first and uses a
  /// bundled preview only when it has none (unencrypted, Bundled +
  /// homeserver).
  static bool homeserverFirstIn(Room room) {
    if (room is! MatrixRoom) return false;
    final settings = MatrixRoomUrlPreviews(room.matrixRoom);
    return homeserverPreviewFirst(
        encrypted: settings.encrypted, mode: settings.mode);
  }

  @override
  UrlPreviewData? getCachedPreview(Timeline timeline, TimelineEvent event) {
    if (event is! TimelineEventMessage) {
      return null;
    }

    final bundled = bundledPreviewFor(timeline, event);
    if (bundled != null && !homeserverFirstIn(timeline.room)) {
      return bundledPreviewData(timeline, event, bundled);
    }

    var uri = previewLinks(timeline, event).firstOrNull;

    if (uri == null) {
      return null;
    }

    final cached = cache[uri.toString()];
    if (bundled != null) {
      if (cached == null && serverSupportsUrlPreview != false) return null;
      return isUsable(cached)
          ? cached
          : bundledPreviewData(timeline, event, bundled, fallback: true);
    }

    return cached;
  }

  @override
  bool shouldGetPreviewsInRoom(Room room) {
    if (!urlPreviewsAllowedIn(room)) {
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

    // Vommet issue 676: a bundled preview needs no homeserver, so neither
    // the encrypted-room default nor server support applies to it.
    if (bundledPreviewFor(timeline, event) != null) {
      return bundledUrlPreviewsAllowedIn(room);
    }

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

  /// Vommet issue 676: the preview the sender bundled for the message's
  /// first previewable link, if it carries data.
  static BundledUrlPreview? bundledPreviewFor(
      Timeline timeline, TimelineEventMessage event) {
    if (event is! MatrixTimelineEventMessage) return null;

    final link = previewLinks(timeline, event).firstOrNull;
    if (link == null || link.authority == "matrix.to") return null;

    return BundledUrlPreview.forLink(
        event.getDisplayEvent(timeline).content, link);
  }

  /// [bundled] as the timeline shows it: the preview, the consent card's
  /// marker, or nothing. [fallback]: the homeserver had no preview for it.
  UrlPreviewData bundledPreviewData(
      Timeline timeline, TimelineEventMessage event, BundledUrlPreview bundled,
      {bool fallback = false}) {
    final room = timeline.room;
    if (room is! MatrixRoom || !bundledUrlPreviewsAllowedIn(room)) {
      return UrlPreviewComponent.invalidPreviewData;
    }

    final mxClient = room.matrixRoom.client;
    final trustVerified = preferences.bundledUrlPreviewsTrustVerified.value;

    final decision = resolveBundledPreview(
        fromSelf: event.senderId == mxClient.userID,
        chatAllowed: localRoomConsent.containsKey(room.identifier)
            ? localRoomConsent[room.identifier]
            : MatrixRoomUrlPreviews(room.matrixRoom).bundledConsent,
        person: bundledPreviewPeople.trustOf(event.senderId),
        trustVerified: trustVerified,
        fromVerifiedSession:
            trustVerified && sentFromVerifiedSession(timeline, event),
        askInNewChats: preferences.bundledUrlPreviewsAskInNewChats.value,
        encrypted: room.matrixRoom.encrypted);

    switch (decision) {
      case BundledPreviewDecision.hide:
        return UrlPreviewComponent.invalidPreviewData;
      case BundledPreviewDecision.ask:
        if (dismissedBundled.contains(event.eventId)) {
          return UrlPreviewComponent.invalidPreviewData;
        }
        return UrlPreviewData(bundled.matchedUrl,
            bundled: true, needsConsent: true, homeserverFallback: fallback);
      case BundledPreviewDecision.show:
        return bundledCache["${event.eventId}|${bundled.matchedUrl}"] ??=
            buildBundledPreview(mxClient, bundled);
    }
  }

  /// Vommet issue 676: whether [event] came encrypted from one of the
  /// sender's sessions that they cross-signed, while you verified them.
  static bool sentFromVerifiedSession(
      Timeline timeline, TimelineEventMessage event) {
    if (event is! MatrixTimelineEventMessage) return false;
    try {
      final shown = event.getDisplayEvent(timeline);
      final original = shown.originalSource;
      if (original == null || original.type != matrix.EventTypes.Encrypted) {
        return false;
      }
      final sessionId = original.content["session_id"];
      if (sessionId is! String) return false;

      final client = shown.room.client;
      final keys = client.userDeviceKeys[shown.senderId];
      if (keys == null || keys.verified != matrix.UserVerifiedStatus.verified) {
        return false;
      }

      final session = client.encryption?.keyManager
          .getInboundGroupSession(shown.room.id, sessionId);
      if (session == null) return false;
      final ed25519 = session.senderClaimedKeys["ed25519"];

      for (final device in keys.deviceKeys.values) {
        if (device.curve25519Key != session.senderKey) continue;
        if (ed25519 != null && device.ed25519Key != ed25519) continue;
        return device.crossVerified && !device.blocked;
      }
    } catch (e) {
      Log.w("Couldn't check the session of a bundled preview: $e");
    }
    return false;
  }

  static UrlPreviewData buildBundledPreview(
      matrix.Client client, BundledUrlPreview bundled) {
    ImageProvider? image;

    // A preview that names another site keeps its text, under a warning,
    // but not its picture (a logo is the most convincing part of a fake).
    final mismatch = bundled.mismatchedHost;

    final mxc = bundled.imageMxc;
    final type = bundled.imageType;
    // The sender states the size; the download is capped as well.
    final decodeHeight = previewImageDecodeHeight(
        bytes: bundled.imageSize,
        width: bundled.imageWidth,
        height: bundled.imageHeight);

    if (mismatch == null &&
        mxc != null &&
        mxc.scheme == "mxc" &&
        decodeHeight != null &&
        (type == null || Mime.displayableImageTypes.contains(type))) {
      final file = bundled.encryptedImage;
      image = LODImageProvider(
        id: "bundled-preview-$mxc-$decodeHeight",
        fullResHeight: decodeHeight,
        loadFullRes: () => downloadBundledImage(client, mxc, file),
      );
    }

    return UrlPreviewData(bundled.matchedUrl,
        siteName: bundled.siteName,
        title: bundled.title,
        description: bundled.description,
        image: image,
        type: UrlDestinationType.page,
        bundled: true,
        mismatchedHost: mismatch);
  }

  /// Downloads a bundled preview image, at most [maxPreviewImageBytes], and
  /// decrypts it when [file] (an EncryptedFile) is given.
  static Future<Uint8List?> downloadBundledImage(
      matrix.Client client, Uri mxc, Map<String, Object?>? file) async {
    try {
      final request = http.Request('GET', await mxc.getDownloadUri(client));
      request.headers['authorization'] = 'Bearer ${client.accessToken}';
      final response = await client.httpClient.send(request);
      if (response.statusCode != 200) return null;

      final length = response.contentLength;
      if (length != null && length > maxPreviewImageBytes) return null;

      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.stream) {
        bytes.add(chunk);
        if (bytes.length > maxPreviewImageBytes) return null;
      }
      final data = bytes.takeBytes();

      if (file == null) return data;

      final key = file["key"] as Map;
      final hashes = file["hashes"] as Map;
      return await client.nativeImplementations.decryptFile(
          matrix.EncryptedFile(
              data: data,
              k: key["k"] as String,
              iv: file["iv"] as String,
              sha256: hashes["sha256"] as String));
    } catch (e) {
      Log.w("Bundled preview image failed: $e");
      return null;
    }
  }

  @override
  Future<void> setBundledConsent(Room room, bool? allowed) async {
    // Shown at once; the account data keeps it for other devices.
    localRoomConsent[room.identifier] = allowed;
    _consentChanges.value++;
    if (room is MatrixRoom) {
      await MatrixRoomUrlPreviews(room.matrixRoom).setBundledConsent(allowed);
    }
  }

  @override
  void dismissBundledPreview(String eventId) => dismissedBundled.add(eventId);

  Map<String, Object?>? get _peopleContent =>
      client.matrixClient.accountData[bundledPreviewsPeopleType]?.content;

  @override
  BundledPreviewPeople get bundledPreviewPeople =>
      _pendingPeople ?? BundledPreviewPeople.fromContent(_peopleContent);

  @override
  Future<void> setBundledPreviewTrust(
      String userId, BundledPreviewPersonTrust? trust) async {
    final mx = client.matrixClient;
    final updated = bundledPreviewPeople.withTrust(userId, trust);
    _pendingPeople = updated;
    _consentChanges.value++;
    try {
      await mx.setAccountData(mx.userID!, bundledPreviewsPeopleType,
          updated.toContent(_peopleContent));
    } catch (_) {
      _pendingPeople = null;
      _consentChanges.value++;
      rethrow;
    }
  }

  /// Choices made on another device (or the echo of this one's) replace the
  /// ones kept locally.
  void _onSync(matrix.SyncUpdate update) {
    var changed = false;
    if (update.accountData?.any((e) => e.type == bundledPreviewsPeopleType) ==
        true) {
      _pendingPeople = null;
      changed = true;
    }
    update.rooms?.join?.forEach((roomId, joined) {
      if (joined.accountData
              ?.any((e) => e.type == bundledPreviewsConsentType) ==
          true) {
        localRoomConsent.remove(roomId);
        changed = true;
      }
    });
    if (changed) _consentChanges.value++;
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
      final cached = cache[uri.toString()];
      // The timeline caches failed fetches as the invalid marker; its
      // placeholder title must not end up in a notification.
      if (cached == UrlPreviewComponent.invalidPreviewData) return null;
      return cached;
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
        description: description,
        previewedBy: client.userID?.domain);
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
