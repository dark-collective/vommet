import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:commet/cache/file_cache.dart';
import 'package:commet/cache/file_provider.dart';
import 'package:commet/client/matrix/matrix_media_privacy.dart';
import 'package:commet/telemetry/telemetry_http.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:http/http.dart' as http;
import 'package:commet/cache/streamable_file_provider.dart';
import 'package:commet/utils/private_files/private_media_files.dart';
import 'package:path/path.dart' as p;

class MxcFileProvider implements FileProvider, StreamableFileProvider {
  final Uri uri;
  final matrix.Client client;
  final matrix.Event? event;
  @override
  String get fileIdentifier => uri.toString();

  MxcFileProvider(this.client, this.uri, {this.event});

  /// Vommet: whether the file is kept sealed in the file cache (media from
  /// an encrypted room).
  bool get sensitive => MatrixMediaPrivacy.isSensitive(event);

  /// Vommet: unencrypted files can be streamed straight from the
  /// homeserver, so a video starts playing before it has fully downloaded
  /// (Vommet issue 338). Encrypted files still need the whole file to
  /// decrypt, and cached files play from the cache. So do files on servers
  /// that don't answer range requests (Vommet issue 529).
  @override
  Future<StreamSource?> getStreamSource() async {
    if (event?.isAttachmentEncrypted == true) return null;
    if (!uri.isScheme("mxc")) return null;

    try {
      if (await fileCache?.hasFile(fileIdentifier, sensitive: sensitive) ==
          true) {
        return null;
      }

      final url = await uri.getDownloadUri(client);
      if (!url.hasScheme) return null;

      final headers = {'authorization': 'Bearer ${client.accessToken}'};
      // Vommet issue 529: a server without range requests can't be
      // streamed from, so download the file first there.
      if (!await serverSupportsRangeRequests(client.httpClient, url,
          headers: headers)) {
        return null;
      }

      return StreamSource(url, headers: headers);
    } catch (e, t) {
      Log.onError(e, t, content: "Failed to get mxc stream url");
      return null;
    }
  }

  StreamController<DownloadProgress> fileDownloadProgress =
      StreamController.broadcast();

  /// Vommet: a file the players can open. Plain media is the cached file
  /// itself. Media from an encrypted room is only ever cached sealed, so it
  /// gets a short-lived private copy ([PrivateMediaFiles]); whoever resolved
  /// it calls [PrivateMediaFiles.release] when done (a no-op for cached
  /// files).
  @override
  Future<Uri?> resolve({String? savePath}) async {
    if (sensitive) {
      // No file cache (web): nothing to resolve to, as before.
      final cache = fileCache;
      if (cache == null) return null;
      File? copy;
      try {
        copy = await PrivateMediaFiles.create(extension: _extension());
        // A cached entry is opened straight into the copy, a segment at a
        // time, so a big video never sits in memory whole.
        if (await cache.openToFile(fileIdentifier, copy.path,
            sensitive: true)) {
          return copy.uri;
        }
        final bytes = await getFileData();
        if (bytes == null) {
          await PrivateMediaFiles.release(copy.uri);
          return null;
        }
        // The player gets its copy first; sealing a big video into the
        // cache takes seconds and only matters for next time, so it runs
        // behind (written beside and renamed, so never half there; dropped
        // if the key is forgotten meanwhile).
        await copy.writeAsBytes(bytes, flush: true);
        sealing = sealInBackground(cache, bytes);
        return copy.uri;
      } catch (error) {
        // No owner-only copy can be made (PrivateFilesUnavailable), or
        // writing it failed: the media isn't opened rather than left
        // readable.
        Log.w("Couldn't make a private copy of encrypted media: $error");
        if (copy != null) await PrivateMediaFiles.release(copy.uri);
        return null;
      }
    }

    var cached = await fileCache?.getFile(fileIdentifier);
    if (cached != null) {
      return cached;
    }

    var bytes = await getFileData();

    if (bytes == null) {
      return null;
    }

    return fileCache?.putFile(fileIdentifier, bytes);
  }

  /// Vommet: the background seal [resolve] started on a cache miss (tests
  /// wait for it).
  Future<void>? sealing;

  /// Vommet: seals [bytes] into [cache] without holding up the caller.
  /// Never throws: a failure is only logged (the entry is then just missing
  /// next time).
  Future<void> sealInBackground(FileCache cache, Uint8List bytes) {
    final done = () async {
      try {
        await cache.writeFile(fileIdentifier, bytes, sensitive: true);
      } catch (error) {
        Log.w("Couldn't cache encrypted media: $error");
      }
    }();
    unawaited(done);
    return done;
  }

  /// The extension of the file's name, so players that go by it know the
  /// format.
  String? _extension() {
    final content = event?.content;
    final name = content?["filename"] ?? content?["body"];
    if (name is! String) return null;
    final ext = p.extension(name);
    return PrivateMediaFiles.safeExtension(ext.isEmpty ? null : ext);
  }

  @override
  Future<void> save(String filepath) async {
    var bytes = await getFileData();
    if (bytes == null) return;

    var file = File(filepath);
    await file.create(recursive: true);
    await file.writeAsBytes(bytes);
  }

  Future<Uint8List?> getFileData() async {
    Uint8List? bytes;

    var cached =
        await fileCache?.readFile(fileIdentifier, sensitive: sensitive);
    if (cached != null) {
      return cached;
    }

    if (event != null) {
      var file = await event!.downloadAndDecryptAttachment(
        downloadCallback: (url) async {
          var request = http.Request("GET", url);
          request.headers
              .addAll({'authorization': 'Bearer ${client.accessToken}'});
          final response =
              await TelemetryHttpClient.wrap(http.Client()).send(request);

          List<int> downloadedBytes = response.contentLength != null
              ? Uint8List(response.contentLength!)
              : [];

          int downloaded = 0;
          if (response.statusCode != 200) {
            throw Exception("Unexpected response: ${response.statusCode}");
          }

          var lastUpdatedProgress = DateTime.now();

          // Vommet: without a Content-Length, fall back to the size the
          // event gives (the same for encrypted files: AES-CTR keeps it).
          final size = event!.infoMap["size"];
          final total =
              response.contentLength ?? (size is int && size > 0 ? size : -1);

          var data = response.stream.listen(
            (event) {
              if (response.contentLength != null) {
                downloadedBytes.setAll(downloaded, event);
              } else {
                downloadedBytes.addAll(event);
              }
              downloaded += event.length;

              var now = DateTime.now();
              if (now.difference(lastUpdatedProgress).inMilliseconds > 16) {
                lastUpdatedProgress = now;

                fileDownloadProgress.add(DownloadProgress(downloaded, total));
              }
            },
            cancelOnError: true,
          ).asFuture();

          await data;

          return Uint8List.fromList(downloadedBytes);
        },
      );
      bytes = file.bytes;
    } else {
      try {
        var response = await client.getContent(uri.authority, uri.path);
        bytes = response.data;
      } catch (e, t) {
        Log.onError(e, t, content: "Failed to get mxc file content");
      }
    }

    return bytes;
  }

  @override
  Stream<DownloadProgress>? get onProgressChanged =>
      fileDownloadProgress.stream;
}
