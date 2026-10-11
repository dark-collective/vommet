import 'dart:io';
import 'dart:typed_data';
import 'package:commet/client/matrix/extensions/matrix_client_extensions.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/utils/mime.dart';
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
                      ))
              : null,
          loadFullRes: (doFullres == null || doFullres == true)
              ? () => retryUntilOnline<Uint8List?>(
                  client,
                  () => loadMatrixFullRes(
                        client,
                        identifier,
                        matrixEvent,
                        cache: cache,
                      ))
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
      var response = scaled
          ? await client.getContentThumbnailFromUri(uri, 800, 600,
              method: Method.scale)
          : await client.getContentThumbnailFromUri(uri, 90, 90);
      bytes = response.data;
    }

    if (bytes != null && cache) {
      fileCache?.putFile(identifier, bytes);
      return bytes;
    }

    return null;
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
