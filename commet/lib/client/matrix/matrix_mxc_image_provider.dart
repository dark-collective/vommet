import 'dart:io';
import 'dart:typed_data';
import 'package:commet/client/matrix/extensions/matrix_client_extensions.dart';
import 'package:commet/client/matrix/matrix_media_failures.dart';
import 'package:commet/client/matrix/matrix_svg_download.dart';
import 'package:commet/utils/image/svg_image.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/utils/mime.dart';
import 'package:commet/utils/media_auto_download.dart';
import 'package:flutter/widgets.dart' show ImageProvider;
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

import '../../utils/image/lod_image.dart';

class MatrixMxcImage extends LODImageProvider {
  Uri identifier;
  Client client;

  /// Vommet: ask the server for a proportionally scaled 800x600 thumbnail
  /// instead of the default 90x90, which servers crop to a square (the
  /// spec's 96x96 size uses the crop method). For banners: the cropped
  /// thumbnail showed a blurry, zoomed-in middle of the picture until the
  /// full image arrived.
  bool scaledThumbnail;

  /// Vommet: the event of an unencrypted picture. Its Media-tab tiles then
  /// use the server's thumbnail of the original at the tile's size
  /// ([forTile], [MatrixServerTileImage]) instead of the original.
  final Event? tileEvent;

  MatrixMxcImage(
    this.identifier,
    this.client, {
    this.scaledThumbnail = false,
    super.blurhash,
    bool? doThumbnail,
    bool? doFullres,
    bool cache = true,
    super.autoLoadFullRes,
    super.useCachedFullRes,
    super.thumbnailTooSmall,
    super.thumbnailHeight,
    super.fullResHeight,
    Event? matrixEvent,
    this.tileEvent,
  }) : super(
          id: "$identifier-$doThumbnail-$doFullres-$thumbnailHeight-$fullResHeight${scaledThumbnail ? "-scaled" : ""}",
          loadThumbnail: (doThumbnail == null || doThumbnail == true)
              ? () => retryUntilOnline<Uint8List?>(
                  client,
                  () => loadMatrixThumbnail(
                        client,
                        identifier,
                        matrixEvent,
                        cache: cache,
                        scaled: scaledThumbnail,
                      )).then((bytes) => drawIfSvg(bytes,
                  height: thumbnailHeight ?? (scaledThumbnail ? 600 : 256)))
              : null,
          loadFullRes: (doFullres == null || doFullres == true)
              ? () => retryUntilOnline<Uint8List?>(
                  client,
                  () => loadMatrixFullRes(
                        client,
                        identifier,
                        matrixEvent,
                        cache: cache,
                      )).then(
                  (bytes) => drawIfSvg(bytes, height: fullResHeight ?? 1024))
              : null,
        );

  /// Vommet: an unencrypted picture's tile is the server's thumbnail of the
  /// original (Media tab: an image without a sender thumbnail downloaded
  /// the whole original, ~1.6 MB, for a ~300 px tile). Encrypted pictures
  /// keep the shared tile: the server can't thumbnail ciphertext.
  @override
  ImageProvider forTile(int pixels) {
    final event = tileEvent;
    if (event == null || event.isAttachmentEncrypted) {
      return super.forTile(pixels);
    }
    return MatrixServerTileImage(
        this, event, LODImageProvider.tileBucket(pixels));
  }

  static String getTileIdentifier(Uri uri, int size) =>
      "matrix_thumbnail_tile$size-$uri";

  static String getThumbnailIdentifier(Uri uri, {bool scaled = false}) {
    if (scaled) return "matrix_thumbnail_scaled-$uri";
    return "matrix_thumbnail-$uri";
  }

  static String getIdentifier(Uri uri) {
    return "matrix-$uri";
  }

  /// Vommet issue 584: the [MatrixMediaFailures] key of a thumbnail or full
  /// image (a cache identifier) for [client]'s account, since another
  /// account's server may fetch the same media fine.
  static String _failureKey(Client client, String identifier) =>
      "${client.userID}|$identifier";

  static Future<T> retryUntilOnline<T>(
      Client client, Future<T> callback()) async {
    try {
      var value = await callback();
      return value;
    } catch (error, trace) {
      if (error is SocketException) {
        while (true) {
          var result = await client.onSyncStatus.stream.first;

          if (result.status == SyncStatus.finished) {
            var result = await callback();
            return result;
          }
        }
      }

      // Vommet: retry other transient failures (rate limiting, gateway
      // errors, dropped connections) twice before giving up. Opening the
      // sticker picker fetches every sticker at once, and one failure left
      // its cell blank.
      Object lastError = error;
      StackTrace lastTrace = trace;
      for (var attempt = 1;
          attempt <= 2 && _isTransient(lastError);
          attempt++) {
        final retryAfter =
            lastError is MatrixException ? lastError.retryAfterMs : null;
        await Future.delayed(retryAfter != null
            ? Duration(milliseconds: retryAfter)
            : Duration(seconds: attempt * 2));
        try {
          return await callback();
        } catch (e, t) {
          lastError = e;
          lastTrace = t;
        }
      }

      // Vommet: rethrow the real error instead of a bare UnimplementedError.
      // Missing media (deleted or purged content, a bad url) is an everyday
      // case, not an app error: the image loader logs it as a warning.
      // A failure replayed from MatrixMediaFailures was logged the first
      // time (Vommet issue 584).
      if ((lastError is! MatrixException ||
              lastError.errcode != "M_NOT_FOUND") &&
          !MatrixMediaFailures.instance.isReplay(lastError)) {
        Log.onError(lastError, lastTrace);
      }
      Error.throwWithStackTrace(lastError, lastTrace);
    }
  }

  static bool _isTransient(Object error) {
    if (error is MatrixException) return error.errcode == "M_LIMIT_EXCEEDED";
    return true;
  }

  /// Vommet: thumbnails downloading at once, per account. A large
  /// account's start asked for hundreds together (one per avatar and preview
  /// on screen), which then timed out together behind the other requests of
  /// the start. Only the download takes a slot (not the cache reads), and a
  /// slot is let go after [thumbnailSlotAtMost] even if the server is still
  /// silent, so a hung download can't block the line.
  static RequestLimiter thumbnailRequestsOf(Client client) =>
      _thumbnailRequests[client] ??=
          RequestLimiter(maxThumbnailRequests, name: 'thumbnails');

  static const int maxThumbnailRequests = 6;
  static const Duration thumbnailSlotAtMost = Duration(seconds: 60);
  static final Expando<RequestLimiter> _thumbnailRequests = Expando();

  static Future<T> _limitedThumbnail<T>(
          Client client, Future<T> Function() download) =>
      thumbnailRequestsOf(client)
          .run(download, holdAtMost: thumbnailSlotAtMost);

  /// The SDK's own download (same request, same handling of the answer),
  /// but in the account's line of thumbnails.
  static Future<Uint8List> Function(Uri) _thumbnailDownload(Client client) =>
      (Uri url) => _limitedThumbnail(client, () async {
            final request = http.Request('GET', url);
            request.headers['authorization'] = 'Bearer ${client.accessToken}';
            final response = await client.httpClient.send(request);
            return response.stream.toBytes();
          });

  static Future<Uint8List?> loadMatrixThumbnail(
    Client client,
    Uri uri,
    Event? matrixEvent, {
    bool cache = true,
    bool scaled = false,
  }) async {
    var identifier = getThumbnailIdentifier(uri, scaled: scaled);

    if (await fileCache?.hasFile(identifier) == true) {
      var cacheUri = await fileCache?.getFile(identifier);

      if (cacheUri != null) {
        return File.fromUri(cacheUri).readAsBytes();
      }
    }

    // Vommet: hold back media the network's auto-download choice skips.
    await _waitForAutoDownload(uri, matrixEvent, thumbnail: true);

    Uint8List? bytes;
    if (matrixEvent != null) {
      // Vommet issue 584: a picture that just failed isn't asked for again.
      var data = await MatrixMediaFailures.instance.guard(
          _failureKey(client, identifier),
          () => matrixEvent.downloadAndDecryptAttachment(
              getThumbnail: true,
              downloadCallback: _thumbnailDownload(client)));

      String mime = matrixEvent.thumbnailMimetype;

      if (mime == "") {
        mime = Mime.lookupType("", data: data.bytes) ?? "";
      }

      if (Mime.imageTypes.contains(mime)) {
        bytes = data.bytes;
      } else {
        Log.w("Attachment thumbnail had unknown mime type: '${mime}'");
      }
    } else {
      bytes = await MatrixMediaFailures.instance.guard(
          _failureKey(client, identifier),
          () => _limitedThumbnail(
              client, () => _serverThumbnail(client, uri, scaled: scaled)));
    }

    if (bytes != null && cache) {
      fileCache?.putFile(identifier, bytes);
      return bytes;
    }

    return null;
  }

  /// Vommet: servers can't thumbnail SVG pictures (Synapse answers 400
  /// "Cannot find any thumbnails"), so an avatar, room icon or emote set as
  /// an SVG showed nothing (Vommet issue 309). When the thumbnail is refused,
  /// the original is used instead if it is a small SVG; anything else keeps
  /// the thumbnail's error.
  static Future<Uint8List> _serverThumbnail(Client client, Uri uri,
      {required bool scaled}) async {
    try {
      var response = scaled
          ? await client.getContentThumbnailFromUri(uri, 800, 600,
              method: Method.scale)
          : await client.getContentThumbnailFromUri(uri, 90, 90);
      return response.data;
    } on MatrixException catch (error) {
      if (!mayTrySvgOriginal(error)) rethrow;

      Uint8List? svg;
      try {
        svg = await client.downloadSmallSvg(uri);
      } on SocketException {
        rethrow;
      } catch (fallbackError) {
        Log.w("Could not fetch the original for an SVG check: $fallbackError");
      }
      if (svg == null) rethrow;
      return svg;
    }
  }

  /// Vommet: whether a refused thumbnail may be an SVG the server can't
  /// thumbnail (Vommet issue 309), so the original is worth a look. Judged by
  /// the errcode: the SDK's media calls throw the error without the HTTP
  /// response, so its status code is always null and the old status check
  /// never let the fallback run (Vommet issue 584). Sign-in errors,
  /// forbidden media, rate limiting and "not yet uploaded" keep the error.
  static bool mayTrySvgOriginal(MatrixException error) {
    final status = error.response?.statusCode;
    if (status == 401 || status == 403 || status == 429) return false;
    return MatrixMediaFailures.isLasting(error) &&
        error.errcode.toUpperCase() != "M_FORBIDDEN";
  }

  /// Vommet: SVG bytes drawn as a PNG [height] pixels high, since the image
  /// codecs can't decode SVG; other bytes are returned as they are. An SVG
  /// that is too big or complex to draw safely shows nothing (Vommet issue
  /// 309).
  static Future<Uint8List?> drawIfSvg(Uint8List? bytes,
      {required int height}) async {
    if (bytes == null || !SvgImage.looksLikeSvg(bytes)) return bytes;

    try {
      final png = await SvgImage.toPng(bytes, height: height);
      if (png == null) Log.w("Not drawing an SVG image: too big or complex");
      return png;
    } catch (error) {
      Log.w("Could not draw an SVG image: $error");
      return null;
    }
  }

  static Future<Uint8List?> loadMatrixFullRes(
    Client client,
    Uri uri,
    Event? matrixEvent, {
    bool cache = true,
  }) async {
    var identifier = getIdentifier(uri);

    if (await fileCache?.hasFile(identifier) == true) {
      var cacheUri = await fileCache?.getFile(identifier);

      if (cacheUri != null) {
        return File.fromUri(cacheUri).readAsBytes();
      }
    }

    // Vommet: hold back media the network's auto-download choice skips.
    await _waitForAutoDownload(uri, matrixEvent);

    Uint8List? bytes;
    final failureKey = _failureKey(client, identifier);
    if (matrixEvent != null) {
      var data = await MatrixMediaFailures.instance
          .guard(failureKey, () => matrixEvent.downloadAndDecryptAttachment());

      bytes = data.bytes;
    } else {
      var response = await MatrixMediaFailures.instance
          .guard(failureKey, () => client.getContentFromUri(uri));
      bytes = response.data;
    }

    if (cache) {
      fileCache?.putFile(identifier, bytes);
      return bytes;
    }

    return null;
  }

  // Vommet: upstream never overrode this, so it was always false; a
  // cached full-size image was ignored after a restart and the 90 px
  // thumbnail shown instead (blurry space banners until reloaded).
  @override
  Future<bool> hasCachedFullres() async {
    var id = getIdentifier(identifier);
    return await fileCache?.hasFile(id) == true;
  }

  @override
  Future<bool> hasCachedThumbnail() async {
    var id = getThumbnailIdentifier(identifier, scaled: scaledThumbnail);
    return await fileCache?.hasFile(id) == true;
  }

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType) return false;
    bool res = other is MatrixMxcImage && other.identifier == identifier;
    return res;
  }

  @override
  int get hashCode => identifier.hashCode;
}

/// Vommet: where a Media-tab tile of an unencrypted picture comes from, in
/// the order tried ([MatrixServerTileImage.steps]).
enum TileSource {
  /// The server's thumbnail of the original at the tile's size.
  server,

  /// The thumbnail the sender attached.
  sender,

  /// The original itself, only when it is small.
  smallOriginal,
}

/// Vommet: a Media-tab tile of an unencrypted picture: the server's thumbnail
/// of the original, cropped to the tile's size, through the thumbnail line,
/// the file cache, the auto-download choice and the failure guard like other
/// thumbnails. The original never downloads for a tile (it does in the
/// viewer); a cached original is still shown, since it costs no data. When
/// the server can't make a thumbnail (an SVG, a 404, a timeout) the
/// sender's thumbnail is used, else the original if it is at most
/// [smallOriginalBytes], else the blurhash stays.
class MatrixServerTileImage extends LODImageProvider {
  MatrixServerTileImage(this.source, this.event, this.size)
      : super(
            id: "${source.identifier}-servertile$size",
            blurhash: source.blurhash,
            thumbnailHeight: 2 * size,
            autoLoadFullRes: false,
            useCachedFullRes: true) {
    fullResLimits = LODImageProvider.tileLimits(size);
    final client = source.client;
    final uri = source.identifier;
    loadThumbnail = () => load(client, uri, event, size);
    // Only ever read from the cache (useCachedFullRes): a tile never
    // downloads the original through here.
    loadFullRes = () => _cachedOriginal(uri);
  }

  final MatrixMxcImage source;
  final Event event;

  /// The tile's bucket, in physical pixels.
  final int size;

  /// The biggest original a tile may fall back to (and the most a small GIF
  /// may be to stay animated in the grid).
  static const int smallOriginalBytes = 512 * 1024;

  /// How long the server gets to make the thumbnail before the next source
  /// is tried.
  static const Duration serverTimeout = Duration(seconds: 30);

  /// The sources tried, in order, for a picture of [mimetype] and
  /// [fileSize] bytes. A small GIF uses its original first so it stays
  /// animated in the grid (server thumbnails are still pictures); servers
  /// can't thumbnail SVG.
  static List<TileSource> steps(
      {required String mimetype,
      required bool hasSenderThumbnail,
      required int? fileSize}) {
    final small = fileSize != null && fileSize <= smallOriginalBytes;
    final gif = mimetype == "image/gif";
    final svg = mimetype == "image/svg+xml";
    return [
      if (gif && small) TileSource.smallOriginal,
      if (!svg) TileSource.server,
      if (hasSenderThumbnail) TileSource.sender,
      if (small && !gif) TileSource.smallOriginal,
    ];
  }

  static List<TileSource> stepsFor(Event event) => steps(
      mimetype: event.attachmentMimetype,
      hasSenderThumbnail: event.hasThumbnail,
      fileSize: event.infoMap['size'] as int?);

  static Future<Uint8List?> _cachedOriginal(Uri uri) async {
    final cacheUri =
        await fileCache?.getFile(MatrixMxcImage.getIdentifier(uri));
    if (cacheUri == null) return null;
    return File.fromUri(cacheUri).readAsBytes();
  }

  /// The tile's picture: the cached server thumbnail, else the first of
  /// [stepsFor] that works; null when none does.
  static Future<Uint8List?> load(
      Client client, Uri uri, Event event, int size) async {
    final identifier = MatrixMxcImage.getTileIdentifier(uri, size);
    final cacheUri = await fileCache?.getFile(identifier);
    if (cacheUri != null) return File.fromUri(cacheUri).readAsBytes();

    await _waitForAutoDownload(uri, event);

    for (final step in stepsFor(event)) {
      try {
        final bytes = switch (step) {
          TileSource.server => await _server(client, uri, size, identifier),
          TileSource.sender =>
            await MatrixMxcImage.loadMatrixThumbnail(client, uri, event),
          TileSource.smallOriginal =>
            await MatrixMxcImage.loadMatrixFullRes(client, uri, event),
        };
        final shown = await MatrixMxcImage.drawIfSvg(bytes, height: 2 * size);
        if (shown != null) return shown;
      } catch (error) {
        if ((error is MatrixException && error.errcode == "M_NOT_FOUND") ||
            MatrixMediaFailures.instance.isReplay(error)) {
          continue;
        }
        Log.w("Media tile: ${step.name} failed: $error");
      }
    }
    return null;
  }

  /// The server's thumbnail, cropped to [size] (the tile draws it with
  /// BoxFit.cover). Queued behind newer tiles: a tile asked for just now is
  /// on screen, older ones may have scrolled away.
  static Future<Uint8List?> _server(
      Client client, Uri uri, int size, String identifier) async {
    final response = await MatrixMediaFailures.instance.guard(
        MatrixMxcImage._failureKey(client, identifier),
        () => MatrixMxcImage.thumbnailRequestsOf(client).run(
            () => client
                .getContentThumbnailFromUri(uri, size, size,
                    method: Method.crop)
                .timeout(serverTimeout),
            priority: RequestPriority.background,
            key: identifier,
            holdAtMost: MatrixMxcImage.thumbnailSlotAtMost));
    final data = response.data;
    if (!Mime.imageTypes.contains(Mime.lookupType("", data: data))) {
      Log.w("Media tile: the server's thumbnail isn't a picture");
      return null;
    }
    fileCache?.putFile(identifier, data);
    return data;
  }

  @override
  Future<bool> hasCachedFullres() => source.hasCachedFullres();

  @override
  Future<bool> hasCachedThumbnail() async =>
      await fileCache?.hasFile(
          MatrixMxcImage.getTileIdentifier(source.identifier, size)) ==
      true;

  @override
  ImageProvider forViewer() => source.forViewer();

  @override
  ImageProvider forTile(int pixels) => source.forTile(pixels);
}

/// Vommet: event media (not avatars, emoji or banners, which have no event)
/// waits until the current network's auto-download choice allows it or it is
/// tapped; your own uploads never wait. The size limit goes by what this
/// download fetches: the thumbnail when loading one, else the file.
Future<void> _waitForAutoDownload(Uri uri, Event? event,
    {bool thumbnail = false}) async {
  if (event == null || event.senderId == event.room.client.userID) return;
  final kind = MediaAutoDownload.kindOf(
      eventType: event.type,
      msgtype: event.messageType,
      mimetype: event.attachmentMimetype,
      fileName: MediaAutoDownload.fileNameOf(event.content));
  if (kind == null) return;
  final size = thumbnail && event.hasThumbnail
      ? event.thumbnailInfoMap["size"]
      : event.infoMap["size"];
  await MediaAutoDownload.waitUntilAllowed(uri.toString(), kind,
      bytes: size is int ? size : null);
}
