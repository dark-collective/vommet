import 'dart:io';
import 'dart:typed_data';

class DownloadProgress {
  int downloaded;
  int total;

  DownloadProgress(this.downloaded, this.total);

  /// Vommet: whether the size is known. Servers that send no Content-Length
  /// (often on mobile) and events without `info.size` leave it at -1.
  bool get hasTotal => total > 0;

  /// How far along the download is (0 to 1), or null when the size is
  /// unknown (an indeterminate spinner instead of a negative value).
  double? get fraction =>
      hasTotal ? (downloaded / total).clamp(0.0, 1.0).toDouble() : null;
}

abstract class FileProvider {
  Future<Uri?> resolve();

  Future<void> save(String filepath);

  Stream<DownloadProgress>? get onProgressChanged;

  Future<Uint8List?> getFileData();

  String get fileIdentifier;
}

class SystemFileProvider implements FileProvider {
  File file;

  @override
  String get fileIdentifier => file.path;

  @override
  Future<Uri?> resolve() async {
    return file.uri;
  }

  @override
  Future<void> save(String filepath) {
    throw UnimplementedError();
  }

  SystemFileProvider(this.file);

  @override
  Stream<DownloadProgress>? get onProgressChanged => null;

  @override
  Future<Uint8List?> getFileData() {
    return file.readAsBytes();
  }
}

class WebFileProvider implements FileProvider {
  Uri url;

  @override
  String get fileIdentifier => url.toString();

  @override
  Future<Uri?> resolve() async {
    throw UnimplementedError();
    //   return file.uri;
  }

  @override
  Future<void> save(String filepath) {
    throw UnimplementedError();
  }

  WebFileProvider(this.url);

  @override
  Stream<DownloadProgress>? get onProgressChanged => null;

  @override
  Future<Uint8List?> getFileData() {
    throw UnimplementedError();
    // return file.readAsBytes();
  }
}
