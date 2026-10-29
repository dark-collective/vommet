import 'package:commet/config/preferences/string_preference.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/utils/media_auto_download.dart';
import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:webrtc_interface/webrtc_interface.dart' as webrtc;

/// When "Use less data for calls" is in effect.
enum CallDataSaverMode {
  never,
  roaming,
  mobile,
  always;

  static CallDataSaverMode fromName(String name) =>
      values.where((m) => m.name == name).firstOrNull ?? mobile;

  /// Whether calls use less data on [network] with this choice.
  bool appliesOn(MediaNetwork network) => switch (this) {
        never => false,
        roaming => network == MediaNetwork.roaming,
        mobile => network != MediaNetwork.wifi,
        always => true,
      };
}

/// Vommet issue 776: "Use less data for calls". On mobile data, roaming or
/// a metered desktop connection (by default), calls send the camera at
/// 360p 15 fps, screen shares at 720p 15 fps 1 Mbps and voice at 32 kbps,
/// and ask for the lowest layer of other people's cameras (a screen share
/// at most the middle one). It overrides the Voice and video settings only
/// while in effect.
class CallDataSaver {
  static final StringPreference mode = StringPreference(
      "vommet_call_data_saver",
      defaultValue: CallDataSaverMode.mobile.name);

  static CallDataSaverMode get currentMode =>
      CallDataSaverMode.fromName(mode.value);

  static const voiceBitrate = 32000;
  static const cameraWidth = 640;
  static const cameraHeight = 360;
  static const cameraFramerate = 15;
  static const cameraBitrate = 300 * 1000;
  static const shareWidth = 1280;
  static const shareHeight = 720;
  static const shareFramerate = 15;
  static const shareBitrate = 1000 * 1000;

  static final ValueNotifier<bool> _active = ValueNotifier(false);
  static bool _started = false;

  /// Whether calls use less data right now; follows the network and the
  /// setting.
  static ValueListenable<bool> get active {
    _start();
    return _active;
  }

  static bool get isActive => active.value;

  static void _start() {
    if (_started) return;
    _started = true;
    MediaAutoDownload.watchNetwork();
    MediaAutoDownload.networkChanges.addListener(_update);
    mode.onChanged.listen((_) => _update());
    _update();
  }

  static void _update() {
    final on = currentMode.appliesOn(MediaAutoDownload.network);
    if (on != _active.value) Log.i("Use less data for calls: $on");
    _active.value = on;
  }

  /// Unit tests only: re-reads the network and the setting.
  @visibleForTesting
  static void updateForTest() {
    _start();
    _update();
  }

  /// Voice bitrate in bits per second.
  static int get voiceBitrateNow => isActive
      ? voiceBitrate
      : (preferences.streamAudioBitrate.value * 1000).toInt();

  static lk.AudioPublishOptions audioPublishOptions() => lk.AudioPublishOptions(
      encoding: lk.AudioEncoding(maxBitrate: voiceBitrateNow));

  /// The camera's capture options, or null for the room's defaults.
  static lk.CameraCaptureOptions? cameraCaptureOptions() => isActive
      ? const lk.CameraCaptureOptions(
          maxFrameRate: cameraFramerate * 1.0,
          params: lk.VideoParameters(
            dimensions: lk.VideoDimensions(cameraWidth, cameraHeight),
            encoding: lk.VideoEncoding(
                maxBitrate: cameraBitrate, maxFramerate: cameraFramerate),
          ))
      : null;

  /// Screen share limits: [bitrate] in bits per second.
  static ({int width, int height, double framerate, int bitrate}) screenShare(
      {required int width,
      required int height,
      required double framerate,
      required int bitrate}) {
    if (!isActive) {
      return (
        width: width,
        height: height,
        framerate: framerate,
        bitrate: bitrate
      );
    }
    final scale = height > shareHeight ? shareHeight / height : 1.0;
    return (
      width: (width * scale).round(),
      height: (height * scale).round(),
      framerate: framerate < shareFramerate ? framerate : shareFramerate * 1.0,
      bitrate: bitrate < shareBitrate ? bitrate : shareBitrate,
    );
  }

  /// The highest layer to receive of someone else's video.
  static lk.VideoQuality receiveQuality({required bool screenShare}) {
    if (!isActive) return lk.VideoQuality.HIGH;
    return screenShare ? lk.VideoQuality.MEDIUM : lk.VideoQuality.LOW;
  }

  /// Classic 1:1 calls: the camera asked for at 360p 15 fps while in
  /// effect. Other constraints are kept.
  static Map<String, dynamic> userMediaConstraints(
      Map<String, dynamic> constraints) {
    final video = constraints["video"];
    if (!isActive || video is! Map) return constraints;
    return {
      ...constraints,
      "video": {
        ...video,
        "width": cameraWidth,
        "height": cameraHeight,
        "frameRate": cameraFramerate,
      },
    };
  }

  /// Sets the maximum bitrate of a published audio track's sender, so a
  /// change of network applies to the running call.
  static Future<void> applyVoiceBitrate(lk.LocalAudioTrack track) async {
    final sender = track.sender;
    if (sender == null) return;
    try {
      final params = sender.parameters;
      final encodings = params.encodings;
      if (encodings == null || encodings.isEmpty) return;
      for (final e in encodings) {
        e.maxBitrate = voiceBitrateNow;
      }
      await sender.setParameters(params);
    } catch (e, s) {
      Log.onError(e, s, content: "Could not change the voice bitrate");
    }
  }
}

/// Classic 1:1 calls: [webrtc.MediaDevices] that asks for a smaller camera
/// while "Use less data for calls" is in effect.
class DataSaverMediaDevices implements webrtc.MediaDevices {
  DataSaverMediaDevices(this._inner);

  final webrtc.MediaDevices _inner;

  @override
  Future<webrtc.MediaStream> getUserMedia(
          Map<String, dynamic> mediaConstraints) =>
      _inner.getUserMedia(CallDataSaver.userMediaConstraints(mediaConstraints));

  @override
  Future<webrtc.MediaStream> getDisplayMedia(
          Map<String, dynamic> mediaConstraints) =>
      _inner.getDisplayMedia(mediaConstraints);

  @override
  // ignore: deprecated_member_use
  Future<List<dynamic>> getSources() => _inner.getSources();

  @override
  Future<List<webrtc.MediaDeviceInfo>> enumerateDevices() =>
      _inner.enumerateDevices();

  @override
  webrtc.MediaTrackSupportedConstraints getSupportedConstraints() =>
      _inner.getSupportedConstraints();

  @override
  Function(dynamic event)? get ondevicechange => _inner.ondevicechange;

  @override
  set ondevicechange(Function(dynamic event)? value) =>
      _inner.ondevicechange = value;

  @override
  Future<webrtc.MediaDeviceInfo> selectAudioOutput(
          [webrtc.AudioOutputOptions? options]) =>
      _inner.selectAudioOutput(options);
}
