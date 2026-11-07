import 'dart:async';
import 'dart:io';

import 'package:commet/client/attachment.dart';
import 'package:commet/utils/private_files/private_media_files.dart';
import 'package:commet/utils/video_trim.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late List<MethodCall> calls;
  late Future<Object?> Function(MethodCall) respond;
  final originalBytes = Uint8List.fromList([1, 2, 3, 4]);
  final exportedBytes = Uint8List.fromList([8, 7, 6]);
  final probe = {
    'cutsUs': [0, 3000000, 9000000],
    'durationUs': 16000000
  };
  final metadata = {
    'durationMs': 12467,
    'width': 240,
    'height': 320,
    'thumbnail': Uint8List.fromList([9])
  };
  PendingFileAttachment original() => PendingFileAttachment(
      name: 'walk.mov', data: originalBytes, mimeType: 'video/mp4', size: 4)
    ..length = const Duration(seconds: 16)
    ..dimensions = const Size(320, 240);
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('vommet-trim-test-');
    PrivateMediaFiles.directoryOverride = directory.path;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    calls = [];
    respond = (call) async {
      if (call.method == 'supported') return true;
      if (call.method == 'probe') return probe;
      if (call.method == 'copy') {
        await File((call.arguments as Map)['target'] as String)
            .writeAsBytes(exportedBytes);
        return metadata;
      }
      return null;
    };
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(VideoTrimJob.channel, (call) async {
      calls.add(call);
      return respond(call);
    });
  });
  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    PrivateMediaFiles.directoryOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(VideoTrimJob.channel, null);
    await directory.delete(recursive: true);
  });
  test(
      'snapped EOF export commits measured metadata, resolves bytes and restores only media',
      () async {
    final file = original();
    final before = file.snapshotForSend();
    final job = VideoTrimJob();
    await job.load(before);
    expect(await job.source!.readAsBytes(), originalBytes);
    final edit = await job.save(before, 1, 3);
    final request =
        calls.singleWhere((c) => c.method == 'copy').arguments as Map;
    expect(request['startUs'], 3000000);
    expect(request['endUs'], isNull);
    job.transferred = true;
    edit.apply(file);
    expect(file.data,
        isNull); // stale picked bytes must never win over the new path
    expect(file.name, 'walk-trim.mp4');
    expect(file.length, const Duration(milliseconds: 12467));
    expect(file.dimensions, const Size(240, 320));
    expect(file.size, exportedBytes.length);
    expect(file.thumbnailFile, [9]);
    await file
        .resolve(); // same operation the send entry points perform before disposal
    expect(file.data, exportedBytes);
    file.spoiler = true;
    file.spoilerReason = 'keep me';
    edit.restore(file);
    expect(file.data, same(originalBytes));
    expect(file.name, 'walk.mov');
    expect(file.length, const Duration(seconds: 16));
    expect(file.spoiler, isTrue);
    expect(file.spoilerReason, 'keep me');
    await job.close();
    expect(await File(edit.output.path!).exists(), isTrue);
    await edit.release();
    expect(await directory.list().toList(), isEmpty);
  });
  test('closing a private preview cannot delete the pending attachment',
      () async {
    final file = original();
    final job = VideoTrimJob();
    await job.load(file);
    final edit = await job.save(file.snapshotForSend(), 1, 3);
    job.transferred = true;
    edit.apply(file);
    final provider = edit.previewProvider!;
    final playback = await provider.resolve();
    expect(playback!.toFilePath(), isNot(edit.output.path));
    expect(await File(playback.toFilePath()).readAsBytes(), exportedBytes);
    await PrivateMediaFiles.release(
        playback); // exactly the existing player's dispose behavior
    expect(await File(edit.output.path!).exists(), isTrue);
    await edit.resolve(file);
    expect(file.data, exportedBytes);
    await edit.release();
    await job.close();
    expect(await provider.resolve(), isNull);
    expect(await directory.list().toList(), isEmpty);
  });
  test('player-owned source is rejected without deleting the caller file',
      () async {
    final picked = await PrivateMediaFiles.create(extension: 'mp4');
    await picked.writeAsBytes(originalBytes);
    final job = VideoTrimJob();
    await expectLater(
        job.load(
            PendingFileAttachment(path: picked.path, mimeType: 'video/mp4')),
        throwsStateError);
    await job.close();
    expect(await picked.readAsBytes(), originalBytes);
    expect(calls, isEmpty);
    await PrivateMediaFiles.release(picked.uri);
  });
  test('interior endpoint is the actual inspected keyframe', () async {
    final job = VideoTrimJob();
    await job.load(original());
    await job.save(original(), 0, 2);
    expect((calls.last.arguments as Map)['endUs'], 9000000);
    await job.close();
    expect(await directory.list().toList(), isEmpty);
  });
  test('no interior cut points and invalid output never alter the original',
      () async {
    final file = original();
    respond = (call) async => call.method == 'probe'
        ? {
            'cutsUs': [0],
            'durationUs': 16000000
          }
        : null;
    final empty = VideoTrimJob();
    await expectLater(empty.load(file), throwsStateError);
    await empty.close();
    respond = (call) async =>
        call.method == 'probe' ? probe : {...metadata, 'durationMs': 0};
    final invalid = VideoTrimJob();
    await invalid.load(file);
    await expectLater(invalid.save(file, 1, 3), throwsStateError);
    await invalid.close();
    expect(file.data, same(originalBytes));
    expect(file.path, isNull);
    expect(await directory.list().toList(), isEmpty);
  });
  test('cancel during probe waits for its result and removes staged source',
      () async {
    final gate = Completer<Object?>(), started = Completer<void>();
    respond = (call) async {
      if (call.method == 'probe') {
        started.complete();
        return gate.future;
      }
      return null;
    };
    final job = VideoTrimJob();
    final load = job.load(original());
    final rejected = expectLater(load, throwsStateError);
    await started.future;
    final close = job.close();
    gate.complete(probe);
    await rejected;
    await close;
    expect(calls.any((c) => c.method == 'cancel'), isTrue);
    expect(await directory.list().toList(), isEmpty);
  });
  test('cancel before staging finishes cannot leak a file', () async {
    final job = VideoTrimJob();
    final load = job.load(original());
    final rejected = expectLater(load, throwsStateError);
    await job.close();
    await rejected;
    expect(await directory.list().toList(), isEmpty);
  });
  test('cancel during copy rejects late success and deletes partial output',
      () async {
    final job = VideoTrimJob();
    await job.load(original());
    final gate = Completer<Object?>(), started = Completer<void>();
    respond = (call) async {
      if (call.method == 'copy') {
        await File((call.arguments as Map)['target'] as String)
            .writeAsBytes(exportedBytes);
        started.complete();
        return gate.future;
      }
      return null;
    };
    final saved = job.save(original(), 1, 3);
    final rejected = expectLater(saved, throwsStateError);
    await started.future;
    final close = job.close();
    gate.complete(metadata);
    await rejected;
    await close;
    expect(await directory.list().toList(), isEmpty);
  });
  test('native availability is required; other platforms do not invoke export',
      () async {
    expect(await VideoTrimJob.available(), isTrue);
    respond = (_) async => false;
    expect(await VideoTrimJob.available(), isFalse);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    calls.clear();
    expect(await VideoTrimJob.available(), isFalse);
    expect(calls, isEmpty);
  });
}
