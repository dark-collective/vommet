import 'dart:io';
import 'package:commet/cache/file_provider.dart';
import 'package:commet/client/attachment.dart';
import 'package:commet/main.dart';
import 'package:commet/utils/download_utils.dart';
import 'package:commet/utils/background_tasks/background_task_manager.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Picker extends FilePicker {
  String? folder;
  var picks = 0;
  @override
  Future<String?> getDirectoryPath(
      {String? dialogTitle,
      bool lockParentWindow = false,
      String? initialDirectory}) async {
    picks++;
    return folder;
  }
}

class _File extends Fake implements FileProvider {
  _File({this.fail = false});
  final bool fail;
  var writes = 0;
  @override
  Stream<DownloadProgress>? get onProgressChanged => null;
  @override
  Future<void> save(String path) async {
    writes++;
    if (fail) throw const FileSystemException('Disk full');
    await File(path).writeAsBytes([1, 2, 3]);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Picker picker;
  late Directory folder;
  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    folder = await Directory.systemTemp.createTemp('vommet-batch-test-');
    picker = _Picker()..folder = folder.path;
    FilePicker.platform = picker;
    backgroundTaskManager = BackgroundTaskManager();
  });
  tearDown(() async {
    for (final sub in backgroundTaskManager.subscriptions.values) {
      await sub.cancel();
    }
    await folder.delete(recursive: true);
  });
  Future<MediaSaveOutcome> save(List<FileAttachment> files, List<int> saved,
          {bool Function()? current}) =>
      DownloadUtils.saveSelectedMedia(files,
          onProgress: (_, __) {},
          onSaved: saved.add,
          shouldContinue: current ?? () => true);
  test(
      'one folder, collision-safe names, and callbacks only after successful writes',
      () async {
    await File('${folder.path}/photo.png').writeAsBytes([0]);
    final a = _File(), b = _File();
    final saved = <int>[];
    expect(
        await save([
          VideoAttachment(a, name: 'photo.png', mimeType: 'video/mp4'),
          VideoAttachment(b, name: 'photo.png', mimeType: 'video/mp4')
        ], saved),
        MediaSaveOutcome.completed);
    expect(picker.picks, 1);
    expect(saved, [0, 1]);
    expect(await File('${folder.path}/photo (2).png').readAsBytes(), [1, 2, 3]);
    expect(await File('${folder.path}/photo (3).png').exists(), isTrue);
    await Future<void>.delayed(const Duration(seconds: 5));
  });
  test('canceling the folder picker never reads files or reports saved',
      () async {
    picker.folder = null;
    final file = _File();
    final saved = <int>[];
    expect(await save([VideoAttachment(file, mimeType: 'video/mp4')], saved),
        MediaSaveOutcome.canceled);
    expect(saved, isEmpty);
    expect(file.writes, 0);
  });
  test(
      'failed write is propagated despite a non-null destination path; stops batch',
      () async {
    final a = _File(fail: true), b = _File();
    final saved = <int>[];
    await expectLater(
        save([
          VideoAttachment(a, mimeType: 'video/mp4'),
          VideoAttachment(b, mimeType: 'video/mp4')
        ], saved),
        throwsA(isA<FileSystemException>()));
    expect(saved, isEmpty);
    expect(b.writes, 0);
    expect(
        backgroundTaskManager.tasks.single.status, BackgroundTaskStatus.failed);
  });
  test(
      'first success survives a later failure without reporting the failed item',
      () async {
    final saved = <int>[];
    await expectLater(
        save([
          VideoAttachment(_File(), mimeType: 'video/mp4'),
          VideoAttachment(_File(fail: true), mimeType: 'video/mp4')
        ], saved),
        throwsA(isA<FileSystemException>()));
    expect(saved, [0]);
    await Future<void>.delayed(const Duration(seconds: 5));
  });
  test('navigation while the picker was open prevents writes', () async {
    final file = _File();
    final saved = <int>[];
    expect(
        await save([VideoAttachment(file, mimeType: 'video/mp4')], saved,
            current: () => false),
        MediaSaveOutcome.canceled);
    expect(saved, isEmpty);
    expect(file.writes, 0);
  });
}
