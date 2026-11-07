import 'dart:io';

import 'package:commet/cache/file_provider.dart';
import 'package:commet/client/attachment.dart';
import 'package:commet/utils/private_files/private_media_files.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

// Vommet issue 1051: original-track trim, restricted to the verified API 35 path.
class VideoTrimEdit {
  VideoTrimEdit(this.original, this.output, this.first, this.last);
  final PendingFileAttachment original, output;
  final int first, last;
  void apply(PendingFileAttachment file) => media(file, output);
  void restore(PendingFileAttachment file) => media(file, original);
  Future<void>? _resolving;
  bool _released = false;
  final _previewReads = <Future<Uri?>>{};
  FileProvider? get previewProvider =>
      output.path == null ? null : _TrimPreview(this);
  Future<Uri?> _preview() {
    if (_released) return Future.value();
    final work = () async {
      final copy = await PrivateMediaFiles.create(extension: 'mp4');
      try {
        await File(output.path!)
            .openRead(0, output.size)
            .pipe(copy.openWrite());
        return copy.uri;
      } catch (_) {
        await PrivateMediaFiles.release(copy.uri);
        rethrow;
      }
    }();
    _previewReads.add(work);
    work.then<void>((_) {
      _previewReads.remove(work);
    }, onError: (Object _) {
      _previewReads.remove(work);
    });
    return work;
  }

  Future<bool> resolve(PendingFileAttachment file) async {
    if (_released) return false;
    try {
      await (_resolving ??= file.resolve());
      if (file.data != null && file.data!.length == output.size) return true;
    } on FileSystemException {
      // The staged output can disappear or become unreadable before Send.
    } finally {
      _resolving = null;
      file.mimeType = output.mimeType;
    }
    file.data = null;
    return false;
  }

  Future<void> release() async {
    _released = true;
    for (final read in _previewReads.toList()) {
      try {
        await read;
      } catch (_) {}
    }
    // Closing the send screen must not unlink a file whose upload bytes are still being read.
    try {
      await _resolving;
    } catch (_) {}
    await PrivateMediaFiles.release(
        output.path == null ? null : Uri.file(output.path!));
  }

  static void media(PendingFileAttachment file, PendingFileAttachment from) {
    file.name = from.name;
    file.path = from.path;
    file.data = from.data;
    file.mimeType = from.mimeType;
    file.size = from.size;
    file.length = from.length;
    file.dimensions = from.dimensions;
    file.thumbnailFile = from.thumbnailFile;
    file.thumbnailMime = from.thumbnailMime;
  }
}

// The existing player owns/deletes each resolved private URI, not the staged attachment.
class _TrimPreview extends SystemFileProvider {
  _TrimPreview(this.edit) : super(File(edit.output.path!));
  final VideoTrimEdit edit;
  @override
  Future<Uri?> resolve() => edit._preview();
}

class VideoTrimJob {
  static const channel = MethodChannel('im.nether.chat/video_trim');
  static int _next = 0;
  static Future<bool> available() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      return await channel.invokeMethod<bool>('supported') ?? false;
    } catch (_) {
      return false;
    }
  }

  File? source, target;
  int? active;
  Future<dynamic>? pending;
  bool canceled = false, transferred = false;
  List<int> cuts = [];

  Future<Map> call(String method, Map<String, Object?> arguments) async {
    if (canceled) throw StateError('canceled');
    active = _next++;
    final work = channel.invokeMapMethod(method, {'id': active, ...arguments});
    try {
      final result = await work;
      if (canceled || result == null) throw StateError('canceled');
      return result;
    } finally {
      active = null;
    }
  }

  Future<void> load(PendingFileAttachment original) {
    final work = _load(original);
    pending = work;
    return work;
  }

  Future<void> _load(PendingFileAttachment original) async {
    // Picked files must outlive this editor; the existing player owns media_open inputs.
    if (original.path != null &&
        await PrivateMediaFiles.isPrivate(original.path!)) {
      throw StateError('player-owned source');
    }
    final bytes = original.data;
    final size = bytes?.length ?? await File(original.path!).length();
    if (size <= 0 || size > 64 * 1024 * 1024) throw StateError('unsupported');
    source = await PrivateMediaFiles.create(extension: 'mp4');
    if (bytes != null) {
      await source!.writeAsBytes(bytes, flush: true);
    } else {
      await File(original.path!).openRead(0, size).pipe(source!.openWrite());
    }
    final info = await call('probe', {'source': source!.path});
    cuts = [...(info['cutsUs'] as List).cast<int>(), info['durationUs'] as int];
    if (cuts.length < 3 ||
        cuts.first != 0 ||
        !List.generate(cuts.length - 1, (i) => cuts[i] < cuts[i + 1])
            .every((v) => v)) {
      throw StateError('no trim points');
    }
  }

  Future<VideoTrimEdit> save(
      PendingFileAttachment original, int first, int last) {
    final work = _save(original, first, last);
    pending = work;
    return work;
  }

  Future<VideoTrimEdit> _save(
      PendingFileAttachment original, int first, int last) async {
    target = await PrivateMediaFiles.create(extension: 'mp4');
    try {
      final info = await call('copy', {
        'source': source!.path,
        'target': target!.path,
        'startUs': cuts[first],
        'endUs': last == cuts.length - 1 ? null : cuts[last]
      });
      final duration = info['durationMs'] as int;
      final width = info['width'] as int, height = info['height'] as int;
      final thumbnail = info['thumbnail'] as Uint8List;
      final size = await target!.length();
      if (canceled ||
          duration <= 0 ||
          width <= 0 ||
          height <= 0 ||
          thumbnail.isEmpty ||
          size <= 0) {
        throw StateError('invalid export');
      }
      final output = PendingFileAttachment(
          name:
              '${(original.name ?? 'video').replaceFirst(RegExp(r'\.[^.]*$'), '')}-trim.mp4',
          path: target!.path,
          mimeType: 'video/mp4',
          size: size)
        ..length = Duration(milliseconds: duration)
        ..dimensions = Size(width.toDouble(), height.toDouble())
        ..thumbnailFile = thumbnail
        ..thumbnailMime = 'image/jpeg';
      return VideoTrimEdit(original, output, first, last);
    } catch (_) {
      await PrivateMediaFiles.release(target?.uri);
      target = null;
      rethrow;
    }
  }

  void cancel() {
    canceled = true;
    if (active != null)
      channel.invokeMethod<void>('cancel', {'id': active}).catchError((_) {});
  }

  Future<void> close() async {
    cancel();
    try {
      await pending;
    } catch (_) {}
    await PrivateMediaFiles.release(source?.uri);
    if (!transferred) await PrivateMediaFiles.release(target?.uri);
  }
}
