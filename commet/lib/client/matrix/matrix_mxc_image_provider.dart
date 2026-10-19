import 'dart:io';
import 'dart:typed_data';
import 'package:commet/client/matrix/extensions/matrix_client_extensions.dart';
import 'package:commet/client/matrix/matrix_svg_download.dart';
import 'package:commet/utils/image/svg_image.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/utils/mime.dart';
import 'package:commet/utils/media_auto_download.dart';
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

  MatrixMxcImage(
    this.identifier,
    this.client, {
    this.scaledThumbnail = false,
    super.blurhash,
    bool? doThumbnail,
    bool? doFullres,
    bool cache = true,
    super.autoLoadFullRes,
    super.thumbnailHeight,
    super.fullResHeight,
    Event? matrixEvent,
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

  static String getThumbnailIdentifier(Uri uri, {bool scaled = false}) {
    if (scaled) return "matrix_thumbnail_scaled-$uri";
    return "matrix_thumbnail-$uri";
  }

  static String getIdentifier(Uri uri) {
    return "matrix-$uri";
  }

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
      if (lastError is! MatrixException || lastError.errcode != "M_NOT_FOUND") {
        Log.onError(lastError, lastTrace);
      }
      Error.throwWithStackTrace(lastError, lastTrace);
    }
  }

  static bool _isTransient(Object error) {
    if (error is MatrixException) return error.errcode == "M_LIMIT_EXCEEDED";
    return true;
  }

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
    await _waitForAutoDownload(uri, matrixEvent);

    Uint8List? bytes;
    if (matrixEvent != null) {
      var data = await matrixEvent.downloadAndDecryptAttachment(
        getThumbnail: true,
      );

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
      bytes = await _serverThumbnail(client, uri, scaled: scaled);
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
      final status = error.response?.statusCode;
      if (status == null || status == 401 || status == 403 || status == 429) {
        rethrow;
      }

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
    if (matrixEvent != null) {
      var data = await matrixEvent.downloadAndDecryptAttachment();

      bytes = data.bytes;
    } else {
      var response = await client.getContentFromUri(uri);
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

/// Vommet: event media (not avatars, emoji or banners, which have no event)
/// waits until the current network's auto-download choice allows it or it is
/// tapped; your own uploads never wait.
Future<void> _waitForAutoDownload(Uri uri, Event? event) async {
  if (event == null || event.senderId == event.room.client.userID) return;
  final kind = MediaAutoDownload.kindOf(
      eventType: event.type,
      msgtype: event.messageType,
      mimetype: event.attachmentMimetype,
      fileName: MediaAutoDownload.fileNameOf(event.content));
  if (kind == null) return;
  await MediaAutoDownload.waitUntilAllowed(uri.toString(), kind);
}
