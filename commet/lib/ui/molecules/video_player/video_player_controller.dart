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

  double _playbackSpeed = 1;
  Future<void> _playbackSpeedQueue = Future.value();

  Future<Uint8List?> Function()? _screenshot;

  Future<Size?> Function()? _getSize;

  Future<Duration> Function()? _getLength;

  Future<double> Function()? _getVolume;

  final StreamController<bool> _isBuffering = StreamController.broadcast();

  final StreamController<DownloadProgress> _downloadProgress =
      StreamController.broadcast();

  final StreamController<bool> _isCompleted = StreamController.broadcast();

  final StreamController<Duration> _onProgressed = StreamController.broadcast();

  final StreamController<double> _onVolumeChanged =
      StreamController.broadcast();

  final StreamController<double> _onPlaybackSpeedChanged =
      StreamController.broadcast();

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
      Future<void> Function(double speed)? setPlaybackSpeed}) {
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
