@TestOn('browser')
library;

import 'dart:typed_data';
import 'package:commet/cache/file_provider.dart';
import 'package:commet/client/attachment.dart';
import 'package:commet/main.dart';
import 'package:commet/utils/background_tasks/background_task_manager.dart';
import 'package:commet/utils/download_utils.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'message_selection_download_test.dart'
    show SelectionMessage, selectionFixture, selectionVideo;

class _BrowserPicker extends FilePicker {
  final names = <String?>[];
  @override
  Future<String?> saveFile(
      {String? dialogTitle,
      String? fileName,
      String? initialDirectory,
      FileType type = FileType.any,
      List<String>? allowedExtensions,
      Uint8List? bytes,
      bool lockParentWindow = false}) async {
    expect(bytes, isNotEmpty);
    names.add(fileName);
    // file_picker's actual web implementation returns null after initiating
    // the anchor download. This is not a cancel/completion signal.
    return null;
  }
}

class _BrowserFile extends Fake implements FileProvider {
  _BrowserFile({this.available = true});
  final bool available;
  var reads = 0;
  @override
  Stream<DownloadProgress>? get onProgressChanged => null;
  @override
  Future<Uint8List?> getFileData() async {
    reads++;
    return available ? Uint8List.fromList([1, 2, 3]) : null;
  }
}

void main() {
  late _BrowserPicker picker;
  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    picker = _BrowserPicker();
    FilePicker.platform = picker;
    backgroundTaskManager = BackgroundTaskManager();
  });
  tearDown(() async {
    for (final sub in backgroundTaskManager.subscriptions.values) {
      await sub.cancel();
    }
  });
  List<FileAttachment> files(_BrowserFile a, _BrowserFile b) => [
        VideoAttachment(a, name: 'same.mp4', mimeType: 'video/mp4'),
        VideoAttachment(b, name: 'same.mp4', mimeType: 'video/mp4'),
      ];
  testWidgets(
      'browser null paths request every selected download with distinct names',
      (t) async {
    final saved = <int>[];
    expect(
        await DownloadUtils.saveSelectedMedia(
            files(_BrowserFile(), _BrowserFile()),
            onProgress: (_, __) {},
            onSaved: saved.add,
            shouldContinue: () => true),
        MediaSaveOutcome.completed);
    expect(saved, [0, 1]);
    expect(picker.names, ['same.mp4', 'same (2).mp4']);
    expect(
        backgroundTaskManager.tasks
            .every((task) => task.status == BackgroundTaskStatus.completed),
        isTrue);
    expect(backgroundTaskManager.tasks.first.label,
        "Download requested for 'same.mp4'");
    await t.pump(const Duration(seconds: 6));
  });
  testWidgets(
      'web batch propagates unavailable bytes and stops after earlier handoffs',
      (t) async {
    final third = _BrowserFile();
    final saved = <int>[];
    await expectLater(
        DownloadUtils.saveSelectedMedia([
          ...files(_BrowserFile(), _BrowserFile(available: false)),
          VideoAttachment(third, name: 'third.mp4', mimeType: 'video/mp4'),
        ],
            onProgress: (_, __) {},
            onSaved: saved.add,
            shouldContinue: () => true),
        throwsA(isA<MediaDownloadException>()));
    expect(saved, [0]);
    expect(picker.names, ['same.mp4']);
    expect(third.reads, 0);
    await t.pump(const Duration(seconds: 6));
  });
  testWidgets(
      'existing mosaic batch also continues after browser handoff nulls',
      (t) async {
    await DownloadUtils.downloadAttachments(
        files(_BrowserFile(), _BrowserFile()));
    expect(picker.names.length, 2);
    await t.pump(const Duration(seconds: 6));
  });
  testWidgets(
      'single-video helper reports successful handoff and rejects failure',
      (t) async {
    expect(
        await DownloadUtils.downloadFile(_BrowserFile(), 'video.mp4'), isTrue);
    expect(
        await DownloadUtils.downloadFile(
            _BrowserFile(available: false), 'missing.mp4'),
        isFalse);
    expect(picker.names, ['video.mp4']);
    await t.pump(const Duration(seconds: 6));
  });
  testWidgets(
      'timeline browser feedback reports requests without claiming completed saves',
      (t) async {
    final selection = selectionFixture([
      SelectionMessage('a', [selectionVideo()]),
      SelectionMessage('b', [selectionVideo()]),
    ]);
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () => selection.save(context),
                    child: const Text('Download'))))));
    await t.tap(find.text('Download'));
    await t.pumpAndSettle();
    expect(
        find.text(
            'Requested 2 downloads. Your browser may ask you to allow multiple downloads.'),
        findsOneWidget);
    expect(find.text('Saved 2 items'), findsNothing);
    expect(selection.active, isFalse);
    await t.pumpWidget(const SizedBox());
    selection.dispose();
    await t.pump();
  });
}
