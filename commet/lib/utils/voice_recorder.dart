import 'dart:async';
import 'dart:io';

import 'package:commet/debug/log.dart';
import 'package:commet/utils/voice_message.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
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

      final dir = await getTemporaryDirectory();
      final path = p.join(dir.path,
          "vommet-voice-${DateTime.now().millisecondsSinceEpoch}.${format.extension}");

      await _recorder.start(
        RecordConfig(
          encoder: format == VoiceFormat.oggOpus
              ? AudioEncoder.opus
              : AudioEncoder.aacLc,
          bitRate: 32000,
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
