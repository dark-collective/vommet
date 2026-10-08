import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/utils/app_focus_util.dart';
import 'package:commet/utils/image_utils.dart';
import 'package:commet/utils/mime.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_blurhash/flutter_blurhash.dart';

enum LODImageType {
  blurhash,
  thumbnail,
  fullres,
}

class LODImageProvider extends ImageProvider<String> {
  LODImageProvider(
      {this.blurhash,
      this.loadThumbnail,
      this.loadFullRes,
      this.thumbnailHeight,
      required this.id,
      this.fullResHeight,
      this.autoLoadFullRes = true});
  String id;
  String? blurhash;
  String? get mimeType => completer?.mimeType;
  bool autoLoadFullRes;
  Future<Uint8List?> Function()? loadThumbnail;
  Future<Uint8List?> Function()? loadFullRes;

  StreamController<void> _lodChangedController = StreamController.broadcast();

  Stream<void> get onLODChanged => _lodChangedController.stream;
  LODImageCompleter? completer;
  int? thumbnailHeight;
  int? fullResHeight;

  Future<bool> hasCachedFullres() async {
    return false;
  }

  Future<bool> hasCachedThumbnail() async {
    return false;
  }

  @override
  Future<String> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<String>(id);
  }

  @override
  void resolveStreamForKey(ImageConfiguration configuration, ImageStream stream,
      String key, ImageErrorListener handleError) {
    super.resolveStreamForKey(configuration, stream, key, handleError);

    completer = stream.completer as LODImageCompleter;
  }

  @override
  ImageStreamCompleter loadImage(String key, ImageDecoderCallback decode) {
    late LODImageCompleter created;
    created = LODImageCompleter(
        blurhash: blurhash,
        loadThumbnail: loadThumbnail,
        loadFullRes: loadFullRes,
        callback: decode,
        onLODChanged: () {
          _lodChangedController.add(null);
        },
        hasCachedFullres: hasCachedFullres,
        hasCachedThumbnail: hasCachedThumbnail,
        thumbnailHeight: thumbnailHeight,
        fullResHeight: fullResHeight,
        autoLoadFullres: autoLoadFullRes,
        // Vommet: a load that failed with nothing shown must not stay in
        // the image cache, or every later use of the image (a sticker
        // picker cell, an emote) reuses the empty completer and stays blank
        // until restart. Evicting it lets the next use load it again.
        onNothingLoaded: () {
          PaintingBinding.instance.imageCache.evict(key);
          if (completer == created) completer = null;
        });
    completer = created;
    return created;
  }

  Future<void> fetchThumbnail() async {
    if (completer == null) {
      ImageUtils.imageProviderToImage(this);
    }

    await completer?.fetchThumbnail();
  }

  Future<void> fetchFullRes() async {
    if (completer == null) {
      ImageUtils.imageProviderToImage(this);
    }

    await completer?.fetchFullRes();
  }
}

class LODImageCompleter extends ImageStreamCompleter {
  String? blurhash;
  Future<bool> Function()? hasCachedThumbnail;
  Future<bool> Function()? hasCachedFullres;
  Future<Uint8List?> Function()? loadThumbnail;
  Future<Uint8List?> Function()? loadFullRes;
  Function()? onLODChanged;
  Function()? onNothingLoaded;
  int _pendingLoads = 0;
  LODImageType? currentlyLoadedImage;
  final double _scale = 1;
  ImageInfo? currentImage;
  FrameInfo? _nextFrame;
  Codec? _codec;
  late Duration _shownTimestamp;
  ImageDecoderCallback callback;
  Duration? _frameDuration;
  bool _frameCallbackScheduled = false;
  bool autoLoadFullres;
  String? mimeType;
  int _framesEmitted = 0;
  int? thumbnailHeight;
  int? fullResHeight;
  double scale = 1;
  Timer? _timer;
  Future? fullResLoading = null;
  Future? thumbnailLoading = null;
  StreamSubscription? appFocusStateSub;

  LODImageCompleter(
      {this.blurhash,
      required this.callback,
      this.loadThumbnail,
      this.loadFullRes,
      this.hasCachedFullres,
      this.hasCachedThumbnail,
      this.thumbnailHeight,
      this.onLODChanged,
      this.fullResHeight,
      this.onNothingLoaded,
      this.autoLoadFullres = true}) {
    loadImages();
  }

  Future<void> loadImages() async {
    if (loadFullRes != null &&
        autoLoadFullres &&
        hasCachedFullres != null &&
        await (hasCachedFullres!.call()) == true) {
      _loadFullRes();
      return;
    }

    if (loadThumbnail != null &&
        hasCachedThumbnail != null &&
        await (hasCachedThumbnail!.call()) == true) {
      _loadThumbnail();
      // Vommet: still fetch the full image when asked to (upstream
      // stopped at the cached thumbnail).
      if (loadFullRes != null && autoLoadFullres) _loadFullRes();
      return;
    }

    if (blurhash != null) _loadBlurhash();
    if (loadThumbnail != null) _loadThumbnail();
    if (loadFullRes != null && autoLoadFullres) _loadFullRes();
  }

  Future<void> _loadBlurhash() async {
    var image =
        await blurHashDecodeImage(blurHash: blurhash!, width: 10, height: 10);

    if (currentlyLoadedImage == null) {
      currentlyLoadedImage = LODImageType.blurhash;
      setImage(ImageInfo(image: image));
    }

    onLODChanged?.call();
  }

  Future<void> _loadThumbnail() async {
    if (thumbnailLoading != null) return thumbnailLoading;
    if (currentlyLoadedImage == LODImageType.thumbnail) return;
    if (currentlyLoadedImage == LODImageType.fullres) return;

    thumbnailLoading = _contained(() async {
      var bytes = await loadThumbnail!.call();
      if (bytes == null) return;

      mimeType = Mime.lookupType("", data: bytes);

      var codec = await callback(
        await ImmutableBuffer.fromUint8List(bytes),
        getTargetSize: (intrinsicWidth, intrinsicHeight) {
          return TargetImageSize(height: thumbnailHeight);
        },
      );

      // Vommet: a thumbnail that finishes after the full image must not
      // replace it.
      if (currentlyLoadedImage == LODImageType.fullres) return;
      await _setCodec(LODImageType.thumbnail, codec);
    });

    await thumbnailLoading;
    thumbnailLoading = null;
    onLODChanged?.call();
  }

  Future<void> fetchFullRes() async {
    return _loadFullRes();
  }

  Future<void> fetchThumbnail() async {
    return _loadThumbnail();
  }

  Future<void> _loadFullRes() async {
    if (fullResLoading != null) {
      return fullResLoading;
    }

    if (currentlyLoadedImage == LODImageType.fullres) {
      return;
    }

    if (loadFullRes == null) {
      return;
    }

    fullResLoading = _contained(() async {
      var bytes = await loadFullRes!.call();
      if (bytes == null) return;

      mimeType = Mime.lookupType("", data: bytes);
      var codec = await callback(
        await ImmutableBuffer.fromUint8List(bytes),
        getTargetSize: (intrinsicWidth, intrinsicHeight) {
          // Vommet: never decode above the image's own size (a larger
          // target upscales in memory for no gain).
          return TargetImageSize(
              height: fullResHeight == null
                  ? null
                  : math.min(fullResHeight!, intrinsicHeight));
        },
      );

      await _setCodec(LODImageType.fullres, codec);
    });

    await fullResLoading;
    fullResLoading = null;
    onLODChanged?.call();
  }

  /// Vommet: runs a load so that a failure (missing media, a corrupt image)
  /// can't escape as an uncaught error and the in-flight future is always
  /// cleared, so the next fetch retries. What is shown (placeholder, blurhash
  /// or the lower LOD) stays and the failure is logged. It is deliberately not
  /// reported to the image stream: Image widgets without an errorBuilder
  /// rethrow stream errors in debug builds, which would just move the crash.
  Future<void> _contained(Future<void> Function() load) async {
    _pendingLoads++;
    try {
      await load();
    } catch (error) {
      Log.w("Couldn't load image: $error");
    } finally {
      _pendingLoads--;
    }
    if (_pendingLoads == 0 && currentlyLoadedImage == null) {
      onNothingLoaded?.call();
    }
  }

  Future<void> _setCodec(LODImageType type, Codec codec) async {
    _codec = codec;
    await _decodeNextFrameAndSchedule();
    currentlyLoadedImage = type;
  }

  Future<void> _decodeNextFrameAndSchedule() async {
    _nextFrame?.image.dispose();
    _nextFrame = null;

    _nextFrame = await _codec!.getNextFrame();

    _emitFrame(ImageInfo(
      image: _nextFrame!.image.clone(),
      scale: _scale,
      debugLabel: debugLabel,
    ));

    if (_codec!.frameCount == 1) {
      _nextFrame!.image.dispose();
      _nextFrame = null;
      return;
    }

    _scheduleAppFrame();
  }

  void _scheduleAppFrame() {
    if (_frameCallbackScheduled) {
      return;
    }
    _frameCallbackScheduled = true;

    SchedulerBinding.instance.scheduleFrameCallback(_handleAppFrame);
  }

  void _handleAppFrame(Duration timestamp) {
    _frameCallbackScheduled = false;
    if (!hasListeners) {
      return;
    }
    assert(_nextFrame != null);
    if (_isFirstFrame() || _hasFrameDurationPassed(timestamp)) {
      _emitFrame(ImageInfo(
        image: _nextFrame!.image.clone(),
        scale: _scale,
        debugLabel: debugLabel,
      ));
      _shownTimestamp = timestamp;
      _frameDuration = _nextFrame!.duration;
      _nextFrame!.image.dispose();
      _nextFrame = null;
      final int completedCycles = _framesEmitted ~/ _codec!.frameCount;
      if (_codec!.repetitionCount == -1 ||
          completedCycles <= _codec!.repetitionCount) {
        _decodeNextFrameAndSchedule();
      }
      return;
    }

    final Duration delay = _frameDuration! - (timestamp - _shownTimestamp);

    if (AppFocus.focused ||
        preferences.pauseAnimationsWhenNotFocused.value == false) {
      _timer?.cancel();

      _timer = Timer(delay * timeDilation, () {
        _scheduleAppFrame();
      });
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void addListener(ImageStreamListener listener) {
    if (!hasListeners &&
        _codec != null &&
        (currentImage == null || _codec!.frameCount > 1)) {
      _decodeNextFrameAndSchedule();
    }

    if (appFocusStateSub == null) {
      appFocusStateSub = AppFocus.focusStateChanged.listen(onAppFocusChanged);
    }
    super.addListener(listener);
  }

  void onAppFocusChanged(void event) {
    if (AppFocus.focused) {
      if (preferences.pauseAnimationsWhenNotFocused.value == true) {
        if (_codec?.frameCount != null && _codec!.frameCount > 1) {
          _timer?.cancel();
          _timer = Timer(_frameDuration ?? Duration(milliseconds: 100), () {
            _decodeNextFrameAndSchedule();
          });
        }
      }
    }
  }

  @override
  void removeListener(ImageStreamListener listener) {
    super.removeListener(listener);
    if (!hasListeners) {
      appFocusStateSub?.cancel();
      appFocusStateSub = null;

      _timer?.cancel();
      _timer = null;
    }
  }

  bool _isFirstFrame() {
    return _frameDuration == null;
  }

  bool _hasFrameDurationPassed(Duration timestamp) {
    return timestamp - _shownTimestamp >= _frameDuration!;
  }

  void _emitFrame(ImageInfo imageInfo) {
    if (!hasListeners) return;
    setImage(imageInfo);
    _framesEmitted += 1;
  }
}
