import 'dart:async';
import 'dart:convert';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/gif/gif_component.dart';
import 'package:commet/client/components/gif/gif_search_result.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_mxc_image_provider.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/client/matrix/matrix_timeline.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/utils/gif_video.dart';
import 'package:commet/utils/mime.dart';
import 'package:flutter/src/painting/image_provider.dart';
import 'package:http/http.dart' as http;

import 'package:matrix/matrix.dart' as matrix;
import 'package:tiamat/config/style/theme_json_converter.dart';

class MatrixFavoriteGif implements FavoriteGif {
  Map<String, dynamic> data;
  MatrixClient client;

  MatrixFavoriteGif(this.client, this.data);

  @override
  double get height {
    var info = data.tryGetMap("info");
    return info?.tryGetDouble("h") ?? 512;
  }

  @override
  ImageProvider<Object> get image {
    var url = data.tryGet<String>("url");
    // Vommet: a GIF saved from an encrypted room before Vommet issue 750
    // keeps its key (`file`), and a bridged GIF is a short video, so both
    // load through an event made from the saved content; the video shows its
    // thumbnail.
    final event = savedEvent;
    if (event != null) {
      return MatrixMxcImage(Uri.parse(url!), client.matrixClient,
          matrixEvent: event, doThumbnail: isVideo, doFullres: !isVideo);
    }
    return MatrixMxcImage(Uri.parse(url!), client.matrixClient,
        doThumbnail: false, doFullres: true);
  }

  /// Vommet: saved from a bridged GIF (a short silent video).
  bool get isVideo => data["msgtype"] == "m.video";

  /// Vommet: whether this is sent as a message (an encrypted file or a video)
  /// instead of as a sticker.
  bool get sendsAsMessage => data["file"] != null || isVideo;

  matrix.Event? get savedEvent {
    if (!sendsAsMessage) return null;
    return matrix.Event(
      content: MatrixGifComponent.messageContent(data),
      type: matrix.EventTypes.Message,
      eventId: "vommet-my-gif-$url",
      senderId: client.matrixClient.userID ?? "",
      originServerTs: DateTime.fromMillisecondsSinceEpoch(0),
      room: matrix.Room(id: "!vommet-my-gifs", client: client.matrixClient),
    );
  }

  @override
  double get width {
    var info = data.tryGetMap("info");
    return info?.tryGetDouble("w") ?? 512;
  }

  @override
  String get url => data.tryGet<String>("url")!;
}

class MatrixGifComponent implements GifComponent<MatrixClient> {
  @override
  MatrixClient client;

  MatrixGifComponent(this.client) {
    client.matrixClient.onSync.stream.listen(_onSync);
  }

  @override
  String get searchPlaceholder => "Search KLIPY";

  static const String favoritesKey = "chat.commet.favorite_stickers";

  StreamController _changedController = StreamController.broadcast();

  @override
  Future<List<GifSearchResult>> search(String query) async {
    // The ui should never actually let the user search if this is disabled, so this *shouldn't* be neccessary
    // but just to be safe!
    if (!preferences.tenorGifSearchEnabled.value) return [];

    var uri = Uri.https(
        preferences.proxyUrl.value, "/proxy/klipy/api/v2/search", {"q": query});

    // var uri =
    //     Uri.http("localhost:8788", "/proxy/klipy/api/v2/search", {"q": query});

    var result = await http.get(uri);
    if (result.statusCode == 200) {
      var data = jsonDecode(result.body) as Map<String, dynamic>;
      var results = data['results'] as List?;

      if (results != null) {
        return results.map((e) => parseTenorResult(e)).toList();
      }
    }

    return [];
  }

  @override
  Stream<dynamic> get onFavoritesChanged => _changedController.stream;

  @override
  Future<TimelineEvent?> sendGif(
      Room room, GifSearchResult gif, TimelineEvent? inReplyTo) async {
    var matrixRoom = (room as MatrixRoom).matrixRoom;
    var response = await matrixRoom.client.httpClient.get(gif.fullResUrl);
    if (response.statusCode == 200) {
      var data = response.bodyBytes;

      matrix.Event? replyingTo;
      var uri = await matrixRoom.client
          .uploadContent(data, filename: "sticker", contentType: gif.mimeType);

      var content = {
        "body": gif.fullResUrl.pathSegments.last,
        "url": uri.toString(),
        if (preferences.stickerCompatibilityMode.value) "msgtype": "m.image",
        if (preferences.stickerCompatibilityMode.value)
          "chat.commet.type": "chat.commet.sticker",
        "info": {
          "chat.commet.animated": true,
          "w": gif.x.toInt(),
          "h": gif.y.toInt(),
          "mimetype": gif.mimeType
        }
      };

      if (inReplyTo != null) {
        replyingTo = await matrixRoom.getEventById(inReplyTo.eventId);
      }

      var id = await matrixRoom.sendEvent(content,
          type: preferences.stickerCompatibilityMode.value
              ? matrix.EventTypes.Message
              : matrix.EventTypes.Sticker,
          inReplyTo: replyingTo);

      if (id != null) {
        var event = await matrixRoom.getEventById(id);
        return room.convertEvent(event!,
            timeline: (room.timeline as MatrixTimeline).matrixTimeline);
      }
    }

    return null;
  }

  GifSearchResult parseTenorResult(Map<String, dynamic> result) {
    const int sizeLimit = 3000000; //3 MB

    var formats = result['media_formats'] as Map<String, dynamic>;

    String mimeType = "image/gif";

    var preview =
        formats['tinygif'] ?? formats['nanogif'] ?? formats['mediumgif'];

    var fullRes = formats['gif'];

    //We only want to send full res if less than 3mb
    if (fullRes['size'] as int > sizeLimit && formats['mediumgif'] != null) {
      fullRes = formats['mediumgif'];
    }

    if (formats["webp"]['size'] < fullRes['size']) {
      fullRes = formats["webp"];
      mimeType = "image/webp";
    }

    if (formats["webp"]['size'] < preview['size']) {
      preview = formats["webp"];
    }

    List<dynamic> dimensions = fullRes['dims']! as List<dynamic>;

    return GifSearchResult(
        convertUrl(preview['url']),
        convertUrl(fullRes['url']),
        (dimensions[0] as int).roundToDouble(),
        (dimensions[1] as int).roundToDouble(),
        mimeType);
  }

  Uri convertUrl(String url) {
    var uri = Uri.parse(url);

    var proxyUri =
        Uri.https(preferences.proxyUrl.value, "/proxy/klipy/media${uri.path}");

    // proxyUri = Uri.http("localhost:8788", "/proxy/klipy/media${uri.path}");

    return proxyUri;
  }

  @override
  bool isGif(TimelineEvent<Client> ev) =>
      isGifEvent((ev as MatrixTimelineEvent).event);

  static bool isGifEvent(matrix.Event event) {
    bool isSticker = event.type == "m.sticker" ||
        (event.type == "m.room.message" &&
            event.content["chat.commet.type"] == "chat.commet.sticker");

    bool isGifMimeType = Mime.gifTypes.contains(event.attachmentMimetype);

    var info = event.content.tryGetMap<String, Object?>("info");

    bool isAnimated = event.attachmentMimetype == "image/gif" ||
        info?["chat.commet.animated"] == true;

    bool isGif = isSticker && isGifMimeType && isAnimated;

    // Vommet: any GIF can go to My GIFs, not only stickers sent from the
    // GIF picker: an uploaded .gif picture, and the short silent videos that
    // bridges post for Telegram and Discord GIFs.
    if (!isGif && !isSticker && event.type == matrix.EventTypes.Message) {
      final msgtype = event.content["msgtype"];
      if (msgtype == "m.image") {
        isGif = event.attachmentMimetype == "image/gif";
      } else if (msgtype == "m.video") {
        isGif = info != null && isGifVideoInfo(info);
      }
    }

    return isGif;
  }

  /// Vommet: the saved entry for [event]. Upstream's entries hold `body`,
  /// `url` and `info`; a bridged GIF also keeps its `msgtype`, so it is sent
  /// back the same way. `url` holds the file's address, which identifies the
  /// entry. A GIF from an encrypted room is saved through
  /// [unencryptedCopyEntry] instead, so no key lands in account data.
  static Map<String, dynamic>? favoriteEntry(matrix.Event event) {
    final url = event.attachmentMxcUrl?.toString();
    if (url == null) return null;
    final isSticker = event.type == matrix.EventTypes.Sticker ||
        event.content["chat.commet.type"] == "chat.commet.sticker";
    final msgtype = event.content.tryGet<String>("msgtype");
    return {
      "info": event.content.tryGetMap<String, Object?>("info"),
      "body": event.content.tryGet<String>("body"),
      "url": url,
      if (!isSticker && msgtype == "m.video") "msgtype": msgtype,
    };
  }

  /// Vommet: the address of the encrypted file an unencrypted copy was made
  /// from, so the original message still shows as saved.
  static const String sourceUrlKey = "im.vommet.source_url";

  /// Vommet: whether the saved [entry] is the GIF at [url], either the file
  /// itself or the encrypted original of an unencrypted copy.
  static bool entryMatches(Map<String, dynamic> entry, String? url) =>
      url != null && (entry["url"] == url || entry[sourceUrlKey] == url);

  /// Vommet (Vommet issue 750): [entry] pointed at an unencrypted copy
  /// uploaded to [url] (and its thumbnail to [thumbnailUrl]). Account data
  /// isn't encrypted, so the entry keeps no `file` or `thumbnail_file` key.
  static Map<String, dynamic> unencryptedCopyEntry(
      Map<String, dynamic> entry, Uri url, Uri? thumbnailUrl) {
    final info = Map<String, Object?>.from(entry["info"] as Map? ?? const {})
      ..remove("thumbnail_file");
    if (thumbnailUrl != null) info["thumbnail_url"] = thumbnailUrl.toString();
    return {
      ...entry,
      "info": info,
      "url": url.toString(),
      sourceUrlKey: entry["url"],
    }..remove("file");
  }

  @override
  bool savesUnencryptedCopy(TimelineEvent<Client> ev) =>
      (ev as MatrixTimelineEvent).event.isAttachmentEncrypted;

  /// Vommet: decrypts [event]'s GIF (and its thumbnail) and uploads them
  /// again unencrypted, returning the entry to save.
  Future<Map<String, dynamic>> _unencryptedCopy(
      matrix.Event event, Map<String, dynamic> entry) async {
    final mx = client.matrixClient;
    final file = await event.downloadAndDecryptAttachment();
    final url = await mx.uploadContent(file.bytes,
        filename: file.name, contentType: file.mimeType);
    Uri? thumbnailUrl;
    if (event.isThumbnailEncrypted) {
      try {
        final thumbnail =
            await event.downloadAndDecryptAttachment(getThumbnail: true);
        thumbnailUrl = await mx.uploadContent(thumbnail.bytes,
            filename: thumbnail.name, contentType: thumbnail.mimeType);
      } catch (e) {
        Log.w("My GIFs: couldn't copy the thumbnail: $e");
      }
    }
    return unencryptedCopyEntry(entry, url, thumbnailUrl);
  }

  /// Vommet: the message sent for a saved encrypted or video GIF.
  static Map<String, dynamic> messageContent(Map<String, dynamic> data) {
    final file = data["file"];
    return {
      "msgtype": data["msgtype"] ?? "m.image",
      "body": data["body"] ?? "GIF",
      if (file != null) "file": file else "url": data["url"],
      if (data["info"] != null) "info": data["info"],
    };
  }

  @override
  Future<void> setFavoriteFromEvent(TimelineEvent<Client> ev) async {
    final event = (ev as MatrixTimelineEvent).event;
    var entry = favoriteEntry(event);
    if (entry == null) return;
    final url = entry["url"] as String;

    var favorites = client.matrixClient.accountData[favoritesKey]?.content
            .tryGetList<Map<String, dynamic>>("favorites") ??
        List<Map<String, dynamic>>.empty();

    if (favorites.any((i) => entryMatches(i, url))) {
      return;
    }

    if (event.isAttachmentEncrypted) {
      entry = await _unencryptedCopy(event, entry);
      favorites = client.matrixClient.accountData[favoritesKey]?.content
              .tryGetList<Map<String, dynamic>>("favorites") ??
          favorites;
    }

    final newFavorites = List.from(favorites, growable: true);
    newFavorites.add(entry);

    await client.matrixClient.setAccountData(
        client.matrixClient.userID!, favoritesKey, {"favorites": newFavorites});
  }

  @override
  bool isFavoriteGif(TimelineEvent<Client> ev) {
    var favorites = client.matrixClient.accountData[favoritesKey]?.content
            .tryGetList<Map<String, dynamic>>("favorites") ??
        List<Map<String, dynamic>>.empty();

    final event = (ev as MatrixTimelineEvent).event;
    final url = event.attachmentMxcUrl?.toString();

    if (favorites.any((i) => entryMatches(i, url))) {
      return true;
    }

    return false;
  }

  @override
  List<FavoriteGif> get favorites {
    var favorites = client.matrixClient.accountData[favoritesKey]?.content
        .tryGetList<Map<String, dynamic>>("favorites");

    if (favorites == null) return [];

    return favorites.map((i) => MatrixFavoriteGif(client, i)).toList();
  }

  @override
  Future<TimelineEvent<Client>?> sendFavoriteGif(
      Room room, FavoriteGif gif, TimelineEvent<Client>? inReplyTo) async {
    var fav = gif as MatrixFavoriteGif;
    matrix.Event? replyingTo;
    var matrixRoom = (room as MatrixRoom).matrixRoom;

    var content = fav.sendsAsMessage
        ? MatrixGifComponent.messageContent(fav.data)
        : {
            "body": fav.data["body"],
            "url": fav.data["url"],
            if (preferences.stickerCompatibilityMode.value)
              "msgtype": "m.image",
            if (preferences.stickerCompatibilityMode.value)
              "chat.commet.type": "chat.commet.sticker",
            "info": fav.data["info"]
          };

    if (inReplyTo != null) {
      replyingTo = await matrixRoom.getEventById(inReplyTo.eventId);
    }

    var id = await matrixRoom.sendEvent(content,
        type: preferences.stickerCompatibilityMode.value || fav.sendsAsMessage
            ? matrix.EventTypes.Message
            : matrix.EventTypes.Sticker,
        inReplyTo: replyingTo);

    if (id != null) {
      var event = await matrixRoom.getEventById(id);
      return room.convertEvent(event!,
          timeline: (room.timeline as MatrixTimeline).matrixTimeline);
    }

    return null;
  }

  @override
  Future<void> removeFavoriteFromEvent(TimelineEvent<Client> ev) async {
    final event = (ev as MatrixTimelineEvent).event;
    var url = event.attachmentMxcUrl?.toString();

    var favorites = client.matrixClient.accountData[favoritesKey]?.content
            .tryGetList<Map<String, dynamic>>("favorites") ??
        List<Map<String, dynamic>>.empty();

    var newFavorites =
        List<Map<String, dynamic>>.from(favorites, growable: true);

    newFavorites.removeWhere((i) => entryMatches(i, url));

    await client.matrixClient.setAccountData(
        client.matrixClient.userID!, favoritesKey, {"favorites": newFavorites});
  }

  void _onSync(matrix.SyncUpdate event) {
    if (event.accountData?.any((i) => i.type == favoritesKey) == true) {
      _changedController.add(null);
    }
  }

  @override
  Future<void> removeFavorite(FavoriteGif gif) async {
    var favorites = client.matrixClient.accountData[favoritesKey]?.content
            .tryGetList<Map<String, dynamic>>("favorites") ??
        List<Map<String, dynamic>>.empty();

    var newFavorites =
        List<Map<String, dynamic>>.from(favorites, growable: true);

    newFavorites.removeWhere((i) => i["url"] == gif.url);

    await client.matrixClient.setAccountData(
        client.matrixClient.userID!, favoritesKey, {"favorites": newFavorites});
  }
}
