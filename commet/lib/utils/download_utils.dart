import 'dart:async';
import 'dart:io';

import 'package:commet/cache/file_provider.dart';
import 'package:commet/client/attachment.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/utils/background_tasks/background_task_manager.dart';
import 'package:commet/utils/file_utils.dart';
import 'package:commet/utils/image_save.dart';
import 'package:commet/utils/mime.dart';
import 'package:commet/utils/private_files/private_media_files.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:mime/mime.dart' as mime;
import 'package:path_provider/path_provider.dart';

/// A checked batch stops at a canceled picker or denied gallery permission.
enum MediaSaveOutcome { completed, canceled, permissionDenied }

typedef SelectedMediaSaver = Future<MediaSaveOutcome> Function(
  List<FileAttachment> files, {
  required void Function(int current, int total) onProgress,
  required void Function(int index) onSaved,
  required bool Function() shouldContinue,
});

class DownloadFileTask
    implements BackgroundTaskWithOptionalProgress, BackgroundTaskWithRetry {
  FileProvider file;
  late String filename;

  String? destinationPath;

  @override
  void Function()? action;

  @override
  bool get canCallAction => destinationPath != null && PlatformUtils.isLinux;

  @override
  void dispose() {
    sub?.cancel();
  }

  @override
  late String label;

  @override
  double? progress = 0;

  @override
  bool shouldRemoveTask = false;

  @override
  String? errorDetail;

  StreamSubscription? sub;
  Object? _failure;
  StackTrace? _failureTrace;

  @override
  BackgroundTaskStatus status = BackgroundTaskStatus.running;

  StreamController controller = StreamController.broadcast();
  @override
  Stream<void> get statusChanged => controller.stream;

  /// Vommet: where to save without asking (desktop "Save all" into a
  /// chosen folder); null to ask with a save dialog.
  final String? savePath;

  DownloadFileTask(this.file, String? fileName, {this.savePath}) {
    filename = fileName ?? "unnamed";

    this.label = "Downloading '$filename'...";

    action = navigateToFile;
  }

  void navigateToFile() {
    if (destinationPath != null) {
      FileUtils.navigateToFile(destinationPath!);
    }
  }

  Future<void> run() async {
    try {
      final saved = await _doDownload();
      if (!saved) {
        shouldRemoveTask = true;
        controller.add(null);
        return;
      }
      status = BackgroundTaskStatus.completed;
      if (kIsWeb) label = downloadFileTaskBrowserRequested(filename);
    } catch (exception, trace) {
      _failure = exception;
      _failureTrace = trace;
      Log.onError(exception, trace);
      status = BackgroundTaskStatus.failed;
      label = "Couldn't download '$filename'";
      errorDetail = _errorDetail(exception);
    }

    controller.add(());

    if (status == BackgroundTaskStatus.completed) {
      Timer(const Duration(seconds: 5), () {
        shouldRemoveTask = true;
        controller.add(null);
      });
    }
  }

  @override
  void retry() {
    dismiss();
    final task = DownloadFileTask(file, filename, savePath: savePath);
    backgroundTaskManager.addTask(task);
    unawaited(task.run());
  }

  @override
  void dismiss() {
    shouldRemoveTask = true;
    controller.add(null);
  }

  static String downloadFileTaskBrowserRequested(String filename) => Intl.message(
      "Download requested for '$filename'",
      args: [filename],
      name: "downloadFileTaskBrowserRequested",
      desc:
          "Background task: bytes handed to the browser, which controls saving");

  static String _errorDetail(Object error) {
    if (error is MediaDownloadException) {
      final code = error.statusCode;
      if (code == 404) {
        return "Server returned 404: the file is no longer on the server.";
      }
      if (code != null && code >= 500) {
        return "Server returned $code: the sender's server may be unreachable.";
      }
      if (code != null) return "Server returned $code.";
    }
    if (error is SocketException ||
        error is TimeoutException ||
        error is http.ClientException) {
      return "The server couldn't be reached.";
    }
    return "The file couldn't be read. It may be damaged.";
  }

  /// Returns false when the user closes the save dialog.
  Future<bool> _doDownload() async {
    sub = file.onProgressChanged?.listen((downloadProgress) {
      final amount = downloadProgress.downloaded.toDouble() /
          downloadProgress.total.toDouble();
      progress = amount;

      controller.add(());
    });

    if (savePath != null && !PlatformUtils.isAndroid && !kIsWeb) {
      destinationPath = savePath;
      await file.save(savePath!);
      return true;
    }

    if (DownloadUtils._saveDialogWritesBytes) {
      final bytes = await file.getFileData();
      if (bytes == null) throw MediaDownloadException();

      destinationPath = await FilePicker.platform.saveFile(
          fileName: DownloadUtils._saveDialogName(filename),
          initialDirectory: preferences.lastDownloadLocation.value,
          bytes: bytes);

      // The web picker returns null after clicking a download link. There is
      // no browser completion/cancel signal; report the handoff, not a write.
      return kIsWeb || destinationPath != null;
    }

    // Vommet issue 900: fetch before the dialog, so a failed download never
    // shows a Save as dialog that then writes nothing.
    final bytes = await file.getFileData();
    if (bytes == null) throw MediaDownloadException();

    final path = await FilePicker.platform.saveFile(
        fileName: filename,
        initialDirectory: preferences.lastDownloadLocation.value);
    if (path == null) return false;

    destinationPath = path;
    await File(path).writeAsBytes(bytes);
    return true;
  }
}

class DownloadUtils {
  // Vommet: export through the iOS document picker (Vommet issue 1054).
  static bool get _usesIOSSaveDialog =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  // The mobile picker requires bytes and writes the file itself.
  static bool get _saveDialogWritesBytes =>
      kIsWeb || PlatformUtils.isAndroid || _usesIOSSaveDialog;

  // The iOS plugin stages the export using this name in Documents.
  static String _saveDialogName(String name) =>
      _usesIOSSaveDialog ? freeFileName(name, (_) => false) : name;

  /// Vommet: "Save as" dialog for bytes already in memory (images from the
  /// viewer, avatars, banners). True when a file was written.
  static Future<bool> saveBytes(Uint8List bytes, String fileName) async {
    if (_saveDialogWritesBytes) {
      final path = await FilePicker.platform.saveFile(
          fileName: _saveDialogName(fileName),
          initialDirectory: preferences.lastDownloadLocation.value,
          bytes: bytes);
      return path != null;
    }

    final path = await FilePicker.platform.saveFile(
        fileName: fileName,
        initialDirectory: preferences.lastDownloadLocation.value);
    if (path == null) return false;
    await File(path).writeAsBytes(bytes);
    return true;
  }

  /// Vommet issue 766: "Save as" for a video in the media viewer, with
  /// the same progress task as an attachment's download.
  static Future<bool> downloadFile(FileProvider file, String name) async {
    final task = DownloadFileTask(file, name);
    backgroundTaskManager.addTask(task);
    await task.run();
    return task.status == BackgroundTaskStatus.completed;
  }

  static Future<void> downloadAttachment(Attachment attachment) async {
    FileProvider? file;
    String name = "untitled";

    if (attachment is FileAttachment) {
      file = attachment.file;
      if (attachment.name != null) {
        name = attachment.name!;
      }
    } else {
      return;
    }

    final task = DownloadFileTask(file, name);
    backgroundTaskManager.addTask(task);
    await task.run();
  }

  /// Vommet: saves a picture mosaic's files ("Save all N"). On a computer
  /// one folder is picked and each file goes in it under its own name (a
  /// free name like "photo (2).jpg" when taken); on a phone or the web each
  /// file gets its own save dialog in turn, stopping at the first cancel.
  static Future<void> downloadAttachments(List<Attachment> attachments) async {
    final files = attachments.whereType<FileAttachment>().toList();
    if (files.isEmpty) return;

    if (PlatformUtils.isAndroid || PlatformUtils.isIOS || kIsWeb) {
      for (final a in files) {
        final task = DownloadFileTask(a.file, a.name ?? "untitled");
        backgroundTaskManager.addTask(task);
        await task.run();
        if (task.status != BackgroundTaskStatus.completed) return;
      }
      return;
    }

    final folder = await FilePicker.platform.getDirectoryPath(
        initialDirectory: preferences.lastDownloadLocation.value);
    if (folder == null) return;

    final used = <String>{};
    for (final a in files) {
      final name = freeFileName(a.name ?? "untitled",
          (n) => used.contains(n) || File("$folder/$n").existsSync());
      used.add(name);
      final task = DownloadFileTask(a.file, name, savePath: "$folder/$name");
      backgroundTaskManager.addTask(task);
      await task.run();
    }
  }

  /// The timeline's checked media batch. Keep the existing platform destinations,
  /// but report a save only after the gallery import / file write completed.
  /// On web, completion means bytes were handed to the browser, not saved.
  /// Successful indices are delivered before a later cancellation or failure.
  static Future<MediaSaveOutcome> saveSelectedMedia(
    List<FileAttachment> files, {
    required void Function(int current, int total) onProgress,
    required void Function(int index) onSaved,
    required bool Function() shouldContinue,
  }) async {
    if (files.isEmpty) return MediaSaveOutcome.completed;
    String? folder;
    if (!canSaveToGallery && !kIsWeb) {
      folder = await FilePicker.platform.getDirectoryPath(
          initialDirectory: preferences.lastDownloadLocation.value);
      if (folder == null) return MediaSaveOutcome.canceled;
    }
    final used = <String>{};
    for (var i = 0; i < files.length; i++) {
      if (!shouldContinue()) return MediaSaveOutcome.canceled;
      final file = files[i];
      onProgress(i + 1, files.length);
      if (canSaveToGallery) {
        // Videos stream to disk; only pictures are loaded into memory.
        final saved = file is VideoAttachment
            ? await saveToGallery([file])
            : await saveViewerMediaToGallery(
                image: file is ImageAttachment ? file.image : null,
                fileName: file.name,
              );
        if (saved == null) return MediaSaveOutcome.permissionDenied;
        if (saved != 1) throw MediaDownloadException();
      } else {
        final name = freeFileName(
            file.name ?? "untitled",
            (name) =>
                used.contains(name) ||
                (folder != null && File("$folder/$name").existsSync()));
        used.add(name);
        final task = DownloadFileTask(file.file, name,
            savePath: folder == null ? null : "$folder/$name");
        backgroundTaskManager.addTask(task);
        await task.run();
        if (task.status == BackgroundTaskStatus.failed) {
          Error.throwWithStackTrace(task._failure!, task._failureTrace!);
        }
        if (task.status != BackgroundTaskStatus.completed) {
          return MediaSaveOutcome.canceled;
        }
      }
      onSaved(i);
    }
    return MediaSaveOutcome.completed;
  }

  /// Vommet issue 882: a phone saves pictures and videos into its gallery.
  static bool get canSaveToGallery =>
      !kIsWeb && (PlatformUtils.isAndroid || PlatformUtils.isIOS);

  /// The gallery album saved pictures and videos go in.
  static const galleryAlbum = "Vommet";

  /// Saves the media viewer's picture or video to the gallery.
  /// Returns null when access is refused. Any decrypted copy is private
  /// and removed after the gallery has imported it, including on failure.
  static Future<int?> saveViewerMediaToGallery({
    ImageProvider? image,
    FileProvider? video,
    String? fileName,
  }) async {
    if (image == null && video == null) return 0;
    if (!await Gal.hasAccess(toAlbum: true) &&
        !await Gal.requestAccess(toAlbum: true)) {
      return null;
    }

    final Uint8List bytes;
    final String extension;
    if (image != null) {
      final result = await ImageSave.bytesOf(image);
      if (result == null) throw MediaDownloadException();
      bytes = result.$1;
      extension = result.$2;
    } else {
      final data = await video!.getFileData();
      if (data == null || data.isEmpty) throw MediaDownloadException();
      bytes = data;
      final detected = Mime.lookupType("", data: bytes);
      final named = Mime.lookupType(fileName ?? "");
      // Prefer a recognized video header to a misleading file name. The
      // MIME package identifies every EBML container as audio/weba; retain
      // a named video container, or use WebM for an unnamed video.
      final mimeType = detected?.startsWith("video/") == true
          ? detected
          : named?.startsWith("video/") == true
              ? named
              : detected == "audio/weba"
                  ? "video/webm"
                  : null;
      extension = PrivateMediaFiles.safeExtension(
              mimeType == null ? null : mime.extensionFromMime(mimeType)) ??
          "mp4";
    }

    final uri = await PrivateMediaFiles.write(bytes, extension: extension);
    try {
      if (image != null) {
        await Gal.putImage(uri.toFilePath(), album: galleryAlbum);
      } else {
        await Gal.putVideo(uri.toFilePath(), album: galleryAlbum);
      }
    } finally {
      await PrivateMediaFiles.release(uri);
    }
    return 1;
  }

  /// Vommet issue 882: saves [attachments]' pictures and videos into the
  /// phone's gallery (album [galleryAlbum]), asking for access first; returns
  /// how many were saved, or null when access is refused. Throws when a
  /// save fails.
  static Future<int?> saveToGallery(List<Attachment> attachments) async {
    final files = attachments
        .whereType<FileAttachment>()
        .where((a) => a is ImageAttachment || a is VideoAttachment)
        .toList();
    if (files.isEmpty) return 0;
    if (!await Gal.hasAccess(toAlbum: true) &&
        !await Gal.requestAccess(toAlbum: true)) {
      return null;
    }

    final dir =
        await (await getTemporaryDirectory()).createTemp("vommet-gallery-");
    var saved = 0;
    try {
      final used = <String>{};
      for (final a in files) {
        final name = freeFileName(a.name ?? "untitled", used.contains);
        used.add(name);
        final path = "${dir.path}/$name";
        await a.file.save(path);
        if (a is VideoAttachment) {
          await Gal.putVideo(path, album: galleryAlbum);
        } else {
          await Gal.putImage(path, album: galleryAlbum);
        }
        saved++;
      }
    } finally {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    }
    return saved;
  }

  /// [name], or "name (2).ext", "name (3).ext"… the first one not [taken].
  /// Path separators in [name] are replaced, so it stays in its folder.
  static String freeFileName(String name, bool Function(String) taken) {
    var safe = name.replaceAll(RegExp(r'[/\\]'), "_").trim();
    if (safe.isEmpty || safe == "." || safe == "..") safe = "untitled";
    if (!taken(safe)) return safe;
    final dot = safe.lastIndexOf(".");
    final stem = dot > 0 ? safe.substring(0, dot) : safe;
    final ext = dot > 0 ? safe.substring(dot) : "";
    for (var i = 2;; i++) {
      final candidate = "$stem ($i)$ext";
      if (!taken(candidate)) return candidate;
    }
  }
}
