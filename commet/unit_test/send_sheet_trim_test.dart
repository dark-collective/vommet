import 'dart:async';

import 'package:commet/client/attachment.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/organisms/attachment_processor/attachment_processor.dart';
import 'package:commet/ui/organisms/attachment_processor/video_gif_trim.dart';
import 'package:commet/ui/organisms/attachment_processor/video_trim.dart';
import 'package:commet/ui/organisms/media_send_sheet/media_send_sheet.dart';
import 'package:commet/utils/video_trim.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

void androidWidgets(String name, WidgetTesterCallback body) =>
    testWidgets(name, body,
        variant: TargetPlatformVariant.only(TargetPlatform.android));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final editor = VideoTrimAction.editor;
  final bytes = Uint8List.fromList([8, 7, 6]);
  final thumbnail = img.encodeJpg(img.Image(width: 4, height: 2));
  PendingFileAttachment video() => PendingFileAttachment(
      name: 'Walk.mp4', mimeType: 'video/mp4', data: Uint8List(32), size: 32);
  VideoTrimEdit made(PendingFileAttachment original) => VideoTrimEdit(
      original.snapshotForSend(),
      PendingFileAttachment(
          name: 'Walk-trim.mp4', mimeType: 'video/mp4', data: bytes, size: 3)
        ..length = const Duration(milliseconds: 12467)
        ..dimensions = const Size(240, 320)
        ..thumbnailFile = thumbnail
        ..thumbnailMime = 'image/jpeg',
      1,
      3);
  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(VideoTrimJob.channel, (_) async => true);
    VideoTrimAction.editor =
        (_, file, edit) async => made(edit?.original ?? file);
  });
  tearDown(() {
    VideoTrimAction.editor = editor;
    // ignore: invalid_use_of_visible_for_testing_member
    MediaSendSheet.debugTrim = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(VideoTrimJob.channel, null);
  });
  androidWidgets('Apply and Reset preserve spoiler and file order',
      (tester) async {
    final file = video()..spoiler = true;
    final other = PendingFileAttachment(
        name: 'notes.pdf', mimeType: 'application/pdf', data: Uint8List(1));
    await tester
        .pumpWidget(MaterialApp(home: MediaSendSheet(files: [file, other])));
    await tester.pumpAndSettle();
    final state =
        tester.state<MediaSendSheetState>(find.byType(MediaSendSheet));
    await tester.tap(find.byKey(const ValueKey('video-trim')));
    await tester.pumpAndSettle();
    expect(file.data, same(bytes));
    expect(file.length, const Duration(milliseconds: 12467));
    expect(file.thumbnailFile, thumbnail);
    expect(file.spoiler, isTrue);
    expect(state.files, [file, other]);
    await tester.tap(find.byKey(const ValueKey('video-trim-reset')));
    await tester.pumpAndSettle();
    expect(file.name, 'Walk.mp4');
    expect(file.data!.length, 32);
    expect(file.length, isNull);
    expect(file.spoiler, isTrue);
  });
  androidWidgets(
      'GIF undo retains measured trim metadata; Reset still restores source',
      (tester) async {
    final file = video();
    await tester.pumpWidget(MaterialApp(home: MediaSendSheet(files: [file])));
    await tester.pumpAndSettle();
    final state =
        tester.state<MediaSendSheetState>(find.byType(MediaSendSheet));
    await tester.tap(find.byKey(const ValueKey('video-trim')));
    await tester.pumpAndSettle();
    // ignore: invalid_use_of_visible_for_testing_member
    MediaSendSheet.debugTrim = (_, __) async => ConvertedGif(
        img.encodeGif(img.Image(width: 4, height: 2)),
        4,
        2,
        const Duration(seconds: 2));
    await state.convertToGif(file);
    await tester.pumpAndSettle();
    state.undoGif(file);
    await tester.pumpAndSettle();
    expect(file.length, const Duration(milliseconds: 12467));
    expect(file.dimensions, const Size(240, 320));
    expect(file.data, same(bytes));
    await tester.tap(find.byKey(const ValueKey('video-trim-reset')));
    await tester.pumpAndSettle();
    expect(file.data!.length, 32);
  });
  androidWidgets('late editor result cannot resurrect a removed file',
      (tester) async {
    final file = video();
    final result = made(file);
    final gate = Completer<VideoTrimEdit?>();
    VideoTrimAction.editor = (_, __, ___) => gate.future;
    final other = PendingFileAttachment(
        name: 'notes.pdf', mimeType: 'application/pdf', data: Uint8List(1));
    await tester
        .pumpWidget(MaterialApp(home: MediaSendSheet(files: [file, other])));
    await tester.pumpAndSettle();
    final state =
        tester.state<MediaSendSheetState>(find.byType(MediaSendSheet));
    await tester.tap(find.byKey(const ValueKey('video-trim')));
    await tester.pump();
    state.remove(file);
    await tester.pumpAndSettle();
    gate.complete(result);
    await tester.pumpAndSettle();
    expect(state.files, [other]);
    expect(file.name, 'Walk.mp4');
    expect(tester.takeException(), isNull);
  });
  for (final sheet in [true, false]) {
    androidWidgets(
        '${sheet ? 'sheet' : 'dialog'} rejects missing trim, then resets and sends measured output',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize =
          sheet ? const Size(390, 844) : const Size(1000, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final file = video();
      Object? sent;
      await tester.pumpWidget(MaterialApp(
          home: Builder(
              builder: (context) => TextButton(
                  onPressed: () async {
                    sent = await Navigator.of(context).push<Object>(
                        MaterialPageRoute(
                            builder: (routeContext) => sheet
                                ? Scaffold(
                                    body: MediaSendSheet(
                                        files: [file],
                                        onResult: (result) =>
                                            Navigator.of(routeContext)
                                                .pop(result)))
                                : Scaffold(
                                    body: SingleChildScrollView(
                                        child: AttachmentProcessor(
                                            attachment: file)))));
                  },
                  child: const Text('Open')))));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      VideoTrimAction.editor = (context, _, __) => showDialog<VideoTrimEdit>(
          context: context,
          builder: (context) =>
              AlertDialog(content: const Text('Child editor'), actions: [
                TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close child'))
              ]));
      await tester.tap(find.byKey(const ValueKey('video-trim')));
      await tester.pumpAndSettle();
      if (sheet) {
        await tester
            .state<MediaSendSheetState>(find.byType(MediaSendSheet))
            .send();
      } else {
        (tester.state(find.byType(AttachmentProcessor)) as dynamic).submit();
      }
      await tester.pumpAndSettle();
      expect(find.text('Child editor'), findsOneWidget);
      await tester.tap(find.text('Close child'));
      await tester.pumpAndSettle();
      VideoTrimAction.editor = (_, f, edit) async => made(edit?.original ?? f);
      await tester.tap(find.byKey(const ValueKey('video-trim')));
      await tester.pumpAndSettle();
      file
        ..data = null
        ..path = '/missing-trim-output.mp4';
      Future<void> submit() async {
        if (sheet) {
          await tester
              .state<MediaSendSheetState>(find.byType(MediaSendSheet))
              .send();
        } else {
          await (tester.state(find.byType(AttachmentProcessor)) as dynamic)
              .submit();
        }
      }

      await tester.runAsync(submit);
      await tester.pumpAndSettle();
      expect(sent, isNull, reason: 'An unreadable trim must not be sent');
      expect(
          find.text(
              'The trimmed video could not be read. Reset trim or try again.'),
          findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('video-trim-reset')));
      await tester.pumpAndSettle();
      expect(file.name, 'Walk.mp4');
      await tester.tap(find.byKey(const ValueKey('video-trim')));
      await tester.pumpAndSettle();
      await submit();
      await tester.pumpAndSettle();
      final output = sheet
          ? (sent as MediaSendResult).files.single
          : sent as PendingFileAttachment;
      expect(output.data, same(bytes));
      expect(output.length, const Duration(milliseconds: 12467));
      expect(output.dimensions, const Size(240, 320));
      expect(output.size, 3);
      expect(output.thumbnailFile, thumbnail);
      expect(tester.takeException(), isNull);
    });
  }
}
