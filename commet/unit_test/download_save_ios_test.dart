import 'package:commet/cache/file_provider.dart';
import 'package:commet/main.dart';
import 'package:commet/utils/background_tasks/background_task_manager.dart';
import 'package:commet/utils/download_utils.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _IOSPicker extends FilePicker {
  String? path;
  String? name;
  Uint8List? data;

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    // file_picker 10.3.10 rejects a path-only save on iOS.
    if (bytes == null) throw ArgumentError.notNull('bytes');
    name = fileName;
    data = bytes;
    return path;
  }
}

class _Video extends Fake implements FileProvider {
  _Video(this.bytes);
  final Uint8List bytes;

  @override
  Stream<DownloadProgress>? get onProgressChanged => null;

  @override
  Future<Uint8List> getFileData() async => bytes;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final bytes = Uint8List.fromList([1, 2, 3]);
  late _IOSPicker picker;

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    picker = _IOSPicker();
    FilePicker.platform = picker;
  });

  for (final cancel in [false, true]) {
    final outcome = cancel ? 'canceled' : 'accepted';
    test('iOS image Save as hands off bytes when $outcome', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      const name = 'folder_photo.png';
      picker.path = cancel ? null : '/files-provider/$name';
      expect(await DownloadUtils.saveBytes(bytes, 'folder/photo.png'), !cancel);
      expect(picker.name, name);
      expect(picker.data, bytes);
    });

    testWidgets('iOS video Save as hands off bytes when $outcome',
        (tester) async {
      const name = 'video.mp4';
      picker.path = cancel ? null : '/files-provider/$name';
      final task = DownloadFileTask(_Video(bytes), name);
      await task.run();

      expect(picker.name, name);
      expect(picker.data, bytes);
      expect(task.destinationPath, picker.path);
      expect(task.shouldRemoveTask, cancel);
      expect(
          task.status,
          cancel
              ? BackgroundTaskStatus.running
              : BackgroundTaskStatus.completed);
      if (!cancel) await tester.pump(const Duration(seconds: 5));
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
  }
}
