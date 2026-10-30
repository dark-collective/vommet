import 'dart:typed_data';

import 'package:commet/cache/file_provider.dart';
import 'package:commet/utils/background_tasks/background_task_manager.dart';
import 'package:commet/utils/download_utils.dart';
import 'package:test/test.dart';

class _FailingFile implements FileProvider {
  _FailingFile(this.error);

  final Object error;

  @override
  String get fileIdentifier => "failing";

  @override
  Future<Uri?> resolve() async => null;

  @override
  Future<void> save(String filepath) async => throw error;

  @override
  Stream<DownloadProgress>? get onProgressChanged => null;

  @override
  Future<Uint8List?> getFileData() async => throw error;
}

void main() {
  test("a failed download stays listed with its cause until dismissed",
      () async {
    final task = DownloadFileTask(
        _FailingFile(MediaDownloadException(404)), "photo.jpg");
    await task.run();

    expect(task.status, BackgroundTaskStatus.failed);
    expect(task.label, "Couldn't download 'photo.jpg'");
    expect(task.errorDetail, contains("404"));
    expect(task.shouldRemoveTask, isFalse);

    task.dismiss();
    expect(task.shouldRemoveTask, isTrue);
  });

  test("a download without a server status still fails with a cause", () async {
    final task =
        DownloadFileTask(_FailingFile(MediaDownloadException()), "photo.jpg");
    await task.run();

    expect(task.status, BackgroundTaskStatus.failed);
    expect(task.errorDetail, isNotNull);
    expect(task.shouldRemoveTask, isFalse);
  });
}
