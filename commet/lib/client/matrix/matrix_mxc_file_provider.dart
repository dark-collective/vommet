import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:commet/cache/file_provider.dart';
import 'package:commet/telemetry/telemetry_http.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:http/http.dart' as http;
import 'package:commet/cache/streamable_file_provider.dart';

class MxcFileProvider implements FileProvider, StreamableFileProvider {
  final Uri uri;
  final matrix.Client client;
  final matrix.Event? event;
  @override
  String get fileIdentifier => uri.toString();

  MxcFileProvider(this.client, this.uri, {this.event});

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
      if (await fileCache?.getFile(fileIdentifier) != null) return null;

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

  @override
  Future<Uri?> resolve({String? savePath}) async {
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

    var cached = await fileCache?.getFile(fileIdentifier);
    if (cached != null) {
      return File.fromUri(cached).readAsBytes();
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
