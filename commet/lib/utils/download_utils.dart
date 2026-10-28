import 'dart:async';
import 'dart:io';

import 'package:commet/cache/file_provider.dart';
import 'package:commet/client/attachment.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/utils/background_tasks/background_task_manager.dart';
import 'package:commet/utils/file_utils.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

class DownloadFileTask implements BackgroundTaskWithOptionalProgress {
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

  StreamSubscription? sub;

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
      var result = await _doDownload();
      status = switch (result) {
        true => BackgroundTaskStatus.completed,
        false => BackgroundTaskStatus.failed,
      };
    } catch (exception, trace) {
      Log.onError(exception, trace);
      status = BackgroundTaskStatus.failed;
    }

    controller.add(());

    Timer(const Duration(seconds: 5), () {
      shouldRemoveTask = true;
      controller.add(null);
    });
  }

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

    if (PlatformUtils.isAndroid || kIsWeb) {
      final bytes = await file.getFileData();
      if (bytes != null) {
        destinationPath = await FilePicker.platform.saveFile(
            fileName: filename,
            initialDirectory: preferences.lastDownloadLocation.value,
            bytes: bytes);

        return destinationPath != null;
      } else {
        return false;
      }
    }

    destinationPath = await FilePicker.platform.saveFile(
        fileName: filename,
        initialDirectory: preferences.lastDownloadLocation.value);

    if (destinationPath != null) {
      await file.save(destinationPath!);
      return true;
    } else {
      return false;
    }
  }
}

class DownloadUtils {
  /// Vommet: "Save as" dialog for bytes already in memory (images from the
  /// viewer, avatars, banners). True when a file was written.
  static Future<bool> saveBytes(Uint8List bytes, String fileName) async {
    if (PlatformUtils.isAndroid || kIsWeb) {
      final path = await FilePicker.platform.saveFile(
          fileName: fileName,
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
    return task.destinationPath != null;
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
        if (task.destinationPath == null) return;
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
