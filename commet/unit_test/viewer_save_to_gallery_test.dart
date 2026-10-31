import 'dart:io';

import 'package:commet/cache/file_provider.dart';
import 'package:commet/utils/download_utils.dart';
import 'package:commet/utils/image/lod_image.dart';
import 'package:commet/utils/private_files/private_media_files.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gal/gal.dart';

class _Video extends Fake implements FileProvider {
  _Video(this.bytes);
  final Uint8List? bytes;
  var reads = 0;

  @override
  Future<Uint8List?> getFileData() async {
    reads++;
    return bytes;
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('gal');
  late Directory directory;
  var hasAccess = true;
  var grantsAccess = true;
  var accessRequests = 0;
  var failSave = false;
  final saves = <(String, String, Uint8List)>[];

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('viewer-gallery-test-');
    PrivateMediaFiles.directoryOverride = '${directory.path}/private';
    hasAccess = true;
    grantsAccess = true;
    accessRequests = 0;
    failSave = false;
    saves.clear();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      final args = call.arguments as Map;
      switch (call.method) {
        case 'hasAccess':
          expect(args['toAlbum'], isTrue);
          return hasAccess;
        case 'requestAccess':
          expect(args['toAlbum'], isTrue);
          accessRequests++;
          return grantsAccess;
        case 'putImage':
        case 'putVideo':
          expect(args['album'], 'Vommet');
          final file = File(args['path'] as String);
          expect(file.path, startsWith('${directory.path}/private/'));
          if (!Platform.isWindows) {
            expect((await file.stat()).mode & 0x1ff, 0x180);
          }
          saves.add((call.method, file.path, await file.readAsBytes()));
          if (failSave) throw PlatformException(code: 'UNEXPECTED');
          return null;
      }
      throw StateError('Unexpected gallery call ${call.method}');
    });
  });

  tearDown(() async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    PrivateMediaFiles.directoryOverride = null;
    await directory.delete(recursive: true);
  });

  // Original files bypass a decoded thumbnail, preserving GIF animation.
  for (final (name, bytes, extension) in [
    ('GIF', Uint8List.fromList('GIF89a-original'.codeUnits), 'gif'),
    ('JPEG', Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0, 1, 2]), 'jpeg'),
  ]) {
    test('saves the original $name, with a matching file type', () async {
      final image = LODImageProvider(
          id: name,
          loadThumbnail: () async => throw StateError('Must use the original'),
          loadFullRes: () async => bytes);
      expect(
          await DownloadUtils.saveViewerMediaToGallery(
              image: image, fileName: 'misleading.png'),
          1);
      expect(saves.single.$1, 'putImage');
      expect(saves.single.$2, endsWith('.$extension'));
      expect(saves.single.$3, bytes);
      expect(await File(saves.single.$2).exists(), isFalse);
    });
  }

  testWidgets('saves a decoded non-Matrix image as PNG', (tester) async {
    // A valid one-pixel PNG from the viewer's existing widget tests.
    final bytes = Uint8List.fromList([
      0x89,
      0x50,
      0x4e,
      0x47,
      0x0d,
      0x0a,
      0x1a,
      0x0a,
      0,
      0,
      0,
      0x0d,
      0x49,
      0x48,
      0x44,
      0x52,
      0,
      0,
      0,
      1,
      0,
      0,
      0,
      1,
      8,
      6,
      0,
      0,
      0,
      0x1f,
      0x15,
      0xc4,
      0x89,
      0,
      0,
      0,
      0x0d,
      0x49,
      0x44,
      0x41,
      0x54,
      0x78,
      0x9c,
      0x63,
      0xf8,
      0xcf,
      0xc0,
      0xf0,
      0x1f,
      0,
      5,
      0,
      1,
      0xff,
      0x89,
      0x99,
      0x3d,
      0x1d,
      0,
      0,
      0,
      0,
      0x49,
      0x45,
      0x4e,
      0x44,
      0xae,
      0x42,
      0x60,
      0x82,
    ]);
    await tester.runAsync(() async {
      expect(
          await DownloadUtils.saveViewerMediaToGallery(
              image: MemoryImage(bytes), fileName: 'picture.jpg'),
          1);
      expect(saves.single.$1, 'putImage');
      expect(saves.single.$2, endsWith('.png'));
      expect(saves.single.$3.take(8), bytes.take(8));
      expect(await File(saves.single.$2).exists(), isFalse);
    });
  });

  test('saves a local video without changing or deleting its source', () async {
    final bytes = Uint8List.fromList([
      0,
      0,
      0,
      0x18,
      0x66,
      0x74,
      0x79,
      0x70,
      0x61,
      0x76,
      0x63,
      0x31,
    ]);
    final source = File('${directory.path}/source.mp4');
    await source.writeAsBytes(bytes);
    // SystemFileProvider.save is unimplemented: gallery saves must use
    // getFileData, which also fetches/decrypts Matrix video providers.
    expect(
        await DownloadUtils.saveViewerMediaToGallery(
            video: SystemFileProvider(source), fileName: '../../clip.webm'),
        1);
    expect(saves.single.$1, 'putVideo');
    expect(saves.single.$2, endsWith('.mp4'));
    expect(saves.single.$3, bytes);
    expect(await File(saves.single.$2).exists(), isFalse);
    expect(await source.readAsBytes(), bytes);
  });

  test('denied gallery access does not download or save the video', () async {
    hasAccess = false;
    grantsAccess = false;
    final video = _Video(Uint8List.fromList([1, 2, 3]));
    expect(await DownloadUtils.saveViewerMediaToGallery(video: video), isNull);
    expect(accessRequests, 1);
    expect(video.reads, 0);
    expect(saves, isEmpty);
    expect(await Directory('${directory.path}/private').exists(), isFalse);
  });

  for (final (name, extension) in [
    ('clip.webm', 'webm'),
    ('clip.mov', 'mov')
  ]) {
    test('keeps the $extension container when video headers are unknown',
        () async {
      final bytes = Uint8List.fromList([1, 2, 3]);
      expect(
          await DownloadUtils.saveViewerMediaToGallery(
              video: _Video(bytes), fileName: name),
          1);
      expect(saves.single.$2, endsWith('.$extension'));
      expect(saves.single.$3, bytes);
    });
  }

  test('an unnamed EBML video stays WebM instead of becoming audio', () async {
    final bytes = Uint8List.fromList([0x1a, 0x45, 0xdf, 0xa3, 1, 2, 3]);
    expect(
        await DownloadUtils.saveViewerMediaToGallery(video: _Video(bytes)), 1);
    expect(saves.single.$1, 'putVideo');
    expect(saves.single.$2, endsWith('.webm'));
    expect(saves.single.$3, bytes);
  });

  test('newly granted access saves into the same gallery album', () async {
    hasAccess = false;
    final video = _Video(Uint8List.fromList([1, 2, 3]));
    expect(await DownloadUtils.saveViewerMediaToGallery(video: video), 1);
    expect(accessRequests, greaterThanOrEqualTo(1));
    expect(saves.single.$1, 'putVideo');
  });

  for (final (label, bytes) in [('missing', null), ('empty', Uint8List(0))]) {
    test('$label video data fails before a gallery import', () async {
      await expectLater(
          DownloadUtils.saveViewerMediaToGallery(video: _Video(bytes)),
          throwsA(isA<MediaDownloadException>()));
      expect(saves, isEmpty);
    });
  }

  test('gallery import errors propagate and delete the private copy', () async {
    failSave = true;
    await expectLater(
        DownloadUtils.saveViewerMediaToGallery(
            video: _Video(Uint8List.fromList([1, 2, 3]))),
        throwsA(isA<GalException>().having(
            (error) => error.type, 'type', GalExceptionType.unexpected)));
    expect(saves, hasLength(1));
    expect(await File(saves.single.$2).exists(), isFalse);
  });
}
