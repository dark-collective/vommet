import 'dart:async';
import 'dart:io';

import 'package:commet/debug/log.dart';
import 'package:commet/utils/private_files/private_media_files.dart';
import 'package:commet/utils/voice_message.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:record/record.dart';

/// Records one voice message at a time from the default microphone.
///
/// Android 10+ and Linux record Ogg/Opus (Linux via parecord + ffmpeg, both
/// in the Flatpak runtime); other platforms record AAC/MP4. While recording,
/// the input level is sampled every 100 ms for the waveform and exposed on
/// [levels] (0..1) for a live meter.
class VoiceRecorder {
  static const sampleInterval = Duration(milliseconds: 100);

  final AudioRecorder _recorder = AudioRecorder();
  final List<double> _dbfs = [];
  final Stopwatch _clock = Stopwatch();
  final StreamController<double> _levels = StreamController.broadcast();
  StreamSubscription<Amplitude>? _amplitudeSub;
  String? _path;
  VoiceFormat? _format;

  Stream<double> get levels => _levels.stream;
  Duration get elapsed => _clock.elapsed;
  bool get isRecording => _path != null;

  /// Encoder bit rate. Voice needs little, but Windows' Media Foundation
  /// AAC encoder only accepts 96, 128, 160 or 192 kbps and fails to start on
  /// anything else (Vommet issue 558), so Windows uses its lowest.
  static int bitRateFor(VoiceFormat format, {required bool windows}) {
    if (windows && format == VoiceFormat.aacMp4) return 96000;
    return 32000;
  }

  /// Starts recording. Returns false (and records nothing) when microphone
  /// permission is missing or the recorder can't start.
  Future<bool> start() async {
    if (isRecording) return true;
    try {
      if (!await _recorder.hasPermission()) return false;

      int? androidSdk;
      if (Platform.isAndroid) {
        androidSdk = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
      }
      final format = VoiceFormat.choose(
          android: Platform.isAndroid,
          linux: Platform.isLinux,
          androidSdk: androidSdk);

      // Vommet: recorded into the app's private directory (0700, not the
      // shared temporary directory) and deleted once read or canceled.
      final path = await PrivateMediaFiles.newPath(extension: format.extension);

      await _recorder.start(
        RecordConfig(
          encoder: format == VoiceFormat.oggOpus
              ? AudioEncoder.opus
              : AudioEncoder.aacLc,
          bitRate: bitRateFor(format, windows: Platform.isWindows),
          sampleRate: format == VoiceFormat.oggOpus ? 48000 : 44100,
          numChannels: 1,
        ),
        path: path,
      );

      _path = path;
      _format = format;
      _dbfs.clear();
      _clock
        ..reset()
        ..start();
      _amplitudeSub = _recorder.onAmplitudeChanged(sampleInterval).listen((a) {
        _dbfs.add(a.current);
        if (!_levels.isClosed) {
          _levels.add(
              VoiceMessage.levelFromDbfs(a.current) / VoiceMessage.waveformMax);
        }
      });
      return true;
    } catch (e, s) {
      Log.onError(e, s, content: "Could not start voice recording");
      await _reset();
      return false;
    }
  }

  /// Stops and returns the recording, or null if nothing usable was recorded.
  Future<VoiceRecording?> stop() async {
    if (!isRecording) return null;
    final duration = _clock.elapsed;
    final format = _format!;
    final samples = List<double>.of(_dbfs);
    String? path;
    try {
      path = await _recorder.stop() ?? _path;
    } catch (e, s) {
      Log.onError(e, s, content: "Could not stop voice recording");
    }
    await _reset();
    if (path == null) return null;

    final file = File(path);
    try {
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return null;
      return VoiceRecording(
        bytes: bytes,
        format: format,
        duration: duration,
        waveform: VoiceMessage.waveformFromDbfs(samples),
      );
    } finally {
      unawaited(file.delete().then((_) => null, onError: (_) => null));
    }
  }

  /// Stops and throws the recording away.
  Future<void> cancel() async {
    if (!isRecording) return;
    final path = _path;
    try {
      await _recorder.cancel();
    } catch (e, s) {
      Log.onError(e, s, content: "Could not cancel voice recording");
    }
    await _reset();
    if (path != null) {
      unawaited(File(path).delete().then((_) => null, onError: (_) => null));
    }
  }

  Future<void> dispose() async {
    await cancel();
    await _levels.close();
    await _recorder.dispose();
  }

  Future<void> _reset() async {
    await _amplitudeSub?.cancel();
    _amplitudeSub = null;
    _clock.stop();
    _path = null;
    _format = null;
  }
}
