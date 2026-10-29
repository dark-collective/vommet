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
import 'package:http/http.dart' as http;

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

  @override
  BackgroundTaskStatus status = BackgroundTaskStatus.running;

  StreamController controller = StreamController.broadcast();
  @override
  Stream<void> get statusChanged => controller.stream;

  DownloadFileTask(this.file, String? fileName) {
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
    } catch (exception, trace) {
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
    final task = DownloadFileTask(file, filename);
    backgroundTaskManager.addTask(task);
    unawaited(task.run());
  }

  @override
  void dismiss() {
    shouldRemoveTask = true;
    controller.add(null);
  }

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

    if (PlatformUtils.isAndroid || kIsWeb) {
      final bytes = await file.getFileData();
      if (bytes == null) throw MediaDownloadException();

      destinationPath = await FilePicker.platform.saveFile(
          fileName: filename,
          initialDirectory: preferences.lastDownloadLocation.value,
          bytes: bytes);

      return destinationPath != null;
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
}
