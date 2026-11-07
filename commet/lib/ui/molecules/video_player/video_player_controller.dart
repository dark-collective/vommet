import 'dart:async';
import 'dart:typed_data';

import 'package:commet/cache/file_provider.dart';
import 'package:flutter/material.dart';

class VideoPlayerController {
  Future<void> Function()? _onPause;

  Future<void> Function()? _onPlay;

  Future<void> Function()? _onReplay;

  Future<void> Function(Duration percent)? _seekTo;

  Future<void> Function(double volume)? _setVolume;

  Future<void> Function(double speed)? _setPlaybackSpeed;

  Duration _position = Duration.zero;
  Duration? _relativeSeekPosition;
  int _pendingRelativeSeeks = 0;
  Future<void> _seekQueue = Future.value();

  double _playbackSpeed = 1;
  Future<void> _playbackSpeedQueue = Future.value();

  Future<Uint8List?> Function()? _screenshot;

  Future<Size?> Function()? _getSize;

  Future<Duration> Function()? _getLength;

  Future<double> Function()? _getVolume;

  Object? _owner;

  final StreamController<bool> _isBuffering = StreamController.broadcast();

  final StreamController<DownloadProgress> _downloadProgress =
      StreamController.broadcast();

  final StreamController<bool> _isCompleted = StreamController.broadcast();

  final StreamController<Duration> _onProgressed = StreamController.broadcast();

  final StreamController<double> _onVolumeChanged =
      StreamController.broadcast();

  final StreamController<double> _onPlaybackSpeedChanged =
      StreamController.broadcast();

  /// Vommet issue 1081: whether the video is playing (for the system's
  /// picture in picture, which only takes a playing video).
  final ValueNotifier<bool> isPlaying = ValueNotifier(false);

  void setPlaying(bool playing) => isPlaying.value = playing;

  Stream<bool> get isBuffering => _isBuffering.stream;

  Stream<bool> get isCompleted => _isCompleted.stream;

  Stream<Duration> get onProgressed => _onProgressed.stream;

  Stream<double> get onVolumeChanged => _onVolumeChanged.stream;

  Stream<double> get onPlaybackSpeedChanged => _onPlaybackSpeedChanged.stream;

  /// Also available before a player attaches, so a preview can select its speed.
  double get playbackSpeed => _playbackSpeed;

  Stream<DownloadProgress> get onDownloadProgressed => _downloadProgress.stream;

  void attach(
      {required Future<void> Function() pause,
      required Future<void> Function() play,
      required Future<void> Function() replay,
      required Future<Duration> Function() getLength,
      required Future<Size?> Function() getSize,
      required Future<double> Function() getVolume,
      Future<Uint8List?> Function()? screenshot,
      required Future<void> Function(Duration percent) seekTo,
      required Future<void> Function(double volume) setVolume,
      Future<void> Function(double speed)? setPlaybackSpeed,
      Object? owner}) {
    _owner = owner;
    _onPause = pause;
    _onPlay = play;
    _onReplay = replay;
    _seekTo = seekTo;
    _getLength = getLength;
    _screenshot = screenshot;
    _getSize = getSize;
    _getVolume = getVolume;
    _setVolume = setVolume;
    _setPlaybackSpeed = setPlaybackSpeed;
  }

  /// Vommet issue 920: [owner] disposed its player. Clears the callbacks so
  /// [attached] is false again, unless another player attached since.
  void detach(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    isPlaying.value = false;
    _onPause = null;
    _onPlay = null;
    _onReplay = null;
    _seekTo = null;
    _getLength = null;
    _screenshot = null;
    _getSize = null;
    _getVolume = null;
    _setVolume = null;
    _setPlaybackSpeed = null;
  }

  /// Vommet issue 838: a player has attached (its size and frames can be
  /// read).
  bool get attached => _getLength != null;

  Future<void> pause() async {
    await _onPause!.call();
  }

  Future<void> play() async {
    await _onPlay?.call();
  }

  Future<void> replay() async {
    await _onReplay!.call();
  }

  Future<void> seekTo(Duration duration) async {
    await _seekTo!.call(duration);
    _position = duration;
  }

  /// Seek without opening unloaded media or changing its playing/paused state.
  /// Queue relative requests so rapid taps accumulate even while the backend
  /// still reports the position from before the previous seek.
  Future<bool> seekRelative(Duration offset) {
    _pendingRelativeSeeks++;
    final operation = _seekQueue.then((_) async {
      if (!attached) return false;
      final length = await getLength();
      if (length <= Duration.zero) return false;
      final target = Duration(
        microseconds: ((_relativeSeekPosition ?? _position) + offset)
            .inMicroseconds
            .clamp(0, length.inMicroseconds),
      );
      await seekTo(target);
      _relativeSeekPosition = target;
      return true;
    });
    _seekQueue = operation.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return operation.whenComplete(() {
      if (--_pendingRelativeSeeks == 0) _relativeSeekPosition = null;
    });
  }

  Future<void> setVolume(double volume) async {
    await _setVolume?.call(volume);
  }

  Future<void> setPlaybackSpeed(double speed) async {
    if (!speed.isFinite || speed <= 0) {
      throw ArgumentError.value(speed, "speed", "Must be positive and finite");
    }
    await _queuePlaybackSpeed(() async {
      await _setPlaybackSpeed?.call(speed);
      if (_playbackSpeed == speed) return;
      _playbackSpeed = speed;
      _onPlaybackSpeedChanged.add(speed);
    });
  }

  /// Restore after opening media, in order with any pending user selections.
  /// Read the cache inside the queue: an earlier selection may still be pending.
  Future<void> reapplyPlaybackSpeed() => _queuePlaybackSpeed(() async {
        await _setPlaybackSpeed?.call(_playbackSpeed);
      });

  Future<void> _queuePlaybackSpeed(Future<void> Function() action) {
    final operation = _playbackSpeedQueue.then((_) => action());
    // A rejected backend update must not block the next selection or restore.
    _playbackSpeedQueue = operation.then<void>((_) {},
        onError: (Object error, StackTrace stack) {});
    return operation;
  }

  Future<Uint8List?> screenshot() async {
    return _screenshot?.call();
  }

  void setBuffering(bool isBuffering) {
    _isBuffering.add(isBuffering);
  }

  void setBufferingProgress(DownloadProgress progress) {
    _downloadProgress.add(progress);
  }

  void setCompleted(bool isBuffering) {
    _isCompleted.add(isBuffering);
  }

  void setProgress(Duration progress) {
    _position = progress;
    _onProgressed.add(progress);
  }

  void handleInternalVolumeChange(double volume) {
    _onVolumeChanged.add(volume);
  }

  Future<Duration> getLength() async {
    return await _getLength!.call();
  }

  Future<Size?> getSize() async {
    return await _getSize!.call();
  }

  Future<double> getVolume() async {
    return await _getVolume!.call();
  }
}
