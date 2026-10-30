import 'package:collection/collection.dart';
import 'package:commet/client/components/voip/voice_filter.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/config/preferences/string_preference.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/utils/audio_output_support.dart'
    if (dart.library.js_interop) 'package:commet/utils/audio_output_support_web.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:intl/intl.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

class WebrtcDefaultDevices {
  /// Vommet: libwebrtc's automatic gain control, behind an experiment.
  /// Applies when the microphone is opened, so a change takes effect on the
  /// next call.
  static bool get useAutoGainControl =>
      preferences.experimentAutoGainControl.value;

  static Future<webrtc.MediaStream?> getDefaultMicrophone() async {
    if (PlatformUtils.isAndroid || PlatformUtils.isWeb) return null;

    await initDummyConnection();
    await VoiceFilter.apply();

    var devices = (await getDevices()).where((i) => i.kind == "audioinput");

    Map<String, dynamic> constraints = {
      'echoCancellation': true,
      'noiseSuppression': VoiceFilter.useWebrtcNoiseSuppression,
      'autoGainControl': useAutoGainControl,
    };

    if (preferences.voipDefaultAudioInput.value != null) {
      var pickedDevice = devices.firstWhereOrNull(
          (i) => i.label == preferences.voipDefaultAudioInput.value);

      if (pickedDevice != null) {
        print(
            "Picked device id: ${pickedDevice.deviceId} (${pickedDevice.label})");
        constraints["deviceId"] = {'exact': pickedDevice.deviceId};

        webrtc.Helper.selectAudioInput(pickedDevice.deviceId);
      } else {
        print("Preferred audio device not found!");
      }
    } else {
      print("No default device set picking first");
    }

    return await webrtc.navigator.mediaDevices
        .getUserMedia({"audio": constraints});
  }

  static Future<List<webrtc.MediaDeviceInfo>> getDevices() async {
    await initDummyConnection();

    var devices = await webrtc.navigator.mediaDevices.enumerateDevices();

    // Vommet: browsers blank every device name until the page has been given
    // microphone access, which left the web settings lists unlabelled. Ask
    // once, drop the stream straight away, and list again.
    if (PlatformUtils.isWeb &&
        devices.isNotEmpty &&
        devices.every((d) => d.label.isEmpty)) {
      try {
        final stream =
            await webrtc.navigator.mediaDevices.getUserMedia({"audio": true});
        for (final track in stream.getTracks()) {
          await track.stop();
        }
        await stream.dispose();
        devices = await webrtc.navigator.mediaDevices.enumerateDevices();
      } catch (e) {
        Log.w("Microphone permission for device names was refused: $e");
      }
    }

    // Vommet: a speaker can't be chosen without setSinkId, so don't list any.
    if (!canPickAudioOutput) {
      devices = devices.where((d) => d.kind != "audiooutput").toList();
    }

    final labelled = withFallbackLabels(devices);
    if (PlatformUtils.isWeb) await _rememberWebChoices(labelled);
    return labelled;
  }

  /// Vommet: false where the browser can't send audio to a chosen speaker
  /// (no HTMLMediaElement.setSinkId: Firefox, Safari), so the web build hides
  /// the speaker picker there instead of offering one that does nothing.
  static bool get canPickAudioOutput =>
      !PlatformUtils.isWeb || browserCanPickAudioOutput();

  /// Vommet: the listed device a saved choice ([label], and on web the
  /// browser's [id]) refers to, or null when it's gone (the browser default
  /// is used then). Both matching wins, then the name, then the id: the name
  /// is what the pickers save, and the id finds the device again after the
  /// browser renames it (e.g. "Microphone 1" until the microphone is
  /// allowed). [byId] defaults to the web build; without it (native) only
  /// the name counts, as before.
  static webrtc.MediaDeviceInfo? findSaved(
      Iterable<webrtc.MediaDeviceInfo> devices,
      {required String? label,
      String? id,
      bool? byId}) {
    if (label == null) return null;
    if (!(byId ?? PlatformUtils.isWeb) || id == null || id.isEmpty) {
      return devices.firstWhereOrNull((d) => d.label == label);
    }
    return devices
            .firstWhereOrNull((d) => d.label == label && d.deviceId == id) ??
        devices.firstWhereOrNull((d) => d.label == label) ??
        devices.firstWhereOrNull((d) => d.deviceId == id);
  }

  static webrtc.MediaDeviceInfo? _savedInput(
          Iterable<webrtc.MediaDeviceInfo> devices) =>
      findSaved(devices.where((d) => d.kind == "audioinput"),
          label: preferences.voipDefaultAudioInput.value,
          id: preferences.voipDefaultAudioInputId.value);

  static webrtc.MediaDeviceInfo? _savedOutput(
          Iterable<webrtc.MediaDeviceInfo> devices) =>
      findSaved(devices.where((d) => d.kind == "audiooutput"),
          label: preferences.voipDefaultAudioOutput.value,
          id: preferences.voipDefaultAudioOutputId.value);

  /// Vommet (web): keep the saved name and id in step with what the browser
  /// lists now, so the pickers show the saved device after a rename and a
  /// newly picked one is remembered by id.
  static Future<void> _rememberWebChoices(
      List<webrtc.MediaDeviceInfo> devices) async {
    Future<void> remember(webrtc.MediaDeviceInfo? device,
        NullableStringPreference label, NullableStringPreference id) async {
      if (label.value == null) {
        if (id.value != null) await id.set(null);
        return;
      }
      if (device == null) return;
      if (device.label != label.value) await label.set(device.label);
      if (device.deviceId.isNotEmpty && device.deviceId != id.value) {
        await id.set(device.deviceId);
      }
    }

    await remember(_savedInput(devices), preferences.voipDefaultAudioInput,
        preferences.voipDefaultAudioInputId);
    await remember(_savedOutput(devices), preferences.voipDefaultAudioOutput,
        preferences.voipDefaultAudioOutputId);
  }

  /// Vommet (web): LiveKit calls in progress, which follow the saved
  /// microphone and speaker when they change.
  static final Set<lk.Room> _webCalls = {};

  /// Vommet (web): send [room]'s audio to the saved speaker, and keep it
  /// following the saved devices until the call ends.
  static Future<void> followSavedDevices(lk.Room room) async {
    if (!PlatformUtils.isWeb || !_webCalls.add(room)) return;
    final listener = room.createListener();
    listener.on<lk.RoomDisconnectedEvent>((_) {
      _webCalls.remove(room);
      listener.dispose();
    });
    await _applyWebOutput();
  }

  static lk.MediaDevice _lkDevice(webrtc.MediaDeviceInfo device) =>
      lk.MediaDevice(
          device.deviceId, device.label, device.kind ?? "", device.groupId);

  static Future<void> _applyWebInput() async {
    if (_webCalls.isEmpty) return;
    final device = _savedInput(await getDevices());
    if (device == null) return;
    for (final room in _webCalls.toList()) {
      try {
        await room.setAudioInputDevice(_lkDevice(device));
      } catch (e) {
        Log.w("Could not switch the call's microphone: $e");
      }
    }
  }

  static Future<void> _applyWebOutput() async {
    if (_webCalls.isEmpty || !canPickAudioOutput) return;
    final device = _savedOutput(await getDevices());
    // An empty id puts the audio back on the browser's default speaker.
    final target = device == null
        ? const lk.MediaDevice("", "", "audiooutput", null)
        : _lkDevice(device);
    for (final room in _webCalls.toList()) {
      try {
        await room.setAudioOutputDevice(target);
      } catch (e) {
        Log.w("Could not switch the call's speaker: $e");
      }
    }
  }

  static String fallbackMicrophoneLabel(int number) => Intl.message(
      "Microphone $number",
      args: [number],
      name: "fallbackMicrophoneLabel",
      desc:
          "Name for a microphone whose real name the browser hides, numbered from 1");

  static String fallbackSpeakerLabel(int number) => Intl.message(
      "Speaker $number",
      args: [number],
      name: "fallbackSpeakerLabel",
      desc:
          "Name for a speaker or headset whose real name the browser hides, numbered from 1");

  static String fallbackCameraLabel(int number) => Intl.message(
      "Camera $number",
      args: [number],
      name: "fallbackCameraLabel",
      desc:
          "Name for a camera whose real name the browser hides, numbered from 1");

  /// Vommet: a device without a name (the browser still hides it, e.g. the
  /// microphone prompt was refused) gets "Microphone 1", "Speaker 2", ...
  /// so the lists aren't blank and the saved choice (kept by name) stays
  /// unique.
  static List<webrtc.MediaDeviceInfo> withFallbackLabels(
      List<webrtc.MediaDeviceInfo> devices) {
    final counts = <String?, int>{};
    return [
      for (final device in devices)
        if (device.label.isNotEmpty)
          device
        else
          webrtc.MediaDeviceInfo(
            deviceId: device.deviceId,
            groupId: device.groupId,
            kind: device.kind,
            label: _fallbackLabel(device.kind,
                counts.update(device.kind, (n) => n + 1, ifAbsent: () => 1)),
          ),
    ];
  }

  static String _fallbackLabel(String? kind, int number) => switch (kind) {
        "audioinput" => fallbackMicrophoneLabel(number),
        "audiooutput" => fallbackSpeakerLabel(number),
        _ => fallbackCameraLabel(number),
      };

  // See: https://github.com/flutter-webrtc/flutter-webrtc/issues/2018#issuecomment-4225654871
  //
  // Vommet: keeping this connection open also keeps libwebrtc's audio device
  // module alive between calls. When the last peer connection closes,
  // libwebrtc terminates the module, and on Linux (PulseAudio backend) the
  // next call's re-initialisation fails ("failed to activate recording" /
  // "playout"): no microphone and no sound in any later call. Reproduced
  // headless in integration_test/voip (2026-10-07); with this connection
  // open, later calls work. Don't remove it without replacing that.
  static bool _hasCreatedDummyConnection = false;
  static Future<void> initDummyConnection() async {
    if (!_hasCreatedDummyConnection) {
      _hasCreatedDummyConnection = true;
      final _ = await webrtc.createPeerConnection(Map());
    }
  }

  static Future<String?> getDefaultMicrophoneId() async {
    // Vommet: the web build uses the saved microphone too (Vommet issue 283).
    if (PlatformUtils.isWeb) return _savedInput(await getDevices())?.deviceId;
    if (PlatformUtils.isAndroid || PlatformUtils.isWeb) return null;

    await initDummyConnection();
    await VoiceFilter.apply();

    var devices = (await getDevices()).where((i) => i.kind == "audioinput");

    if (preferences.voipDefaultAudioInput.value == null) return null;

    return devices
        .firstWhereOrNull(
            (i) => i.label == preferences.voipDefaultAudioInput.value)
        ?.deviceId;
  }

  static Future<void> selectInputDevice() async {
    if (PlatformUtils.isWeb) return _applyWebInput();

    var devices = (await getDevices()).where((i) => i.kind == "audioinput");

    if (preferences.voipDefaultAudioInput.value != null) {
      var pickedDevice = devices.firstWhereOrNull(
          (i) => i.label == preferences.voipDefaultAudioInput.value);

      if (pickedDevice != null) {
        print(
            "Picked device id: ${pickedDevice.deviceId} (${pickedDevice.label})");

        webrtc.Helper.selectAudioInput(pickedDevice.deviceId);
      } else {
        print("Preferred audio device not found!");
      }
    }
  }

  static Future<void> selectOutputDevice() async {
    if (PlatformUtils.isWeb) return _applyWebOutput();

    if (preferences.voipDefaultAudioOutput.value == null) return;

    var devices = (await getDevices()).where((i) => i.kind == "audiooutput");

    var device = devices.firstWhereOrNull(
        (i) => i.label == preferences.voipDefaultAudioOutput.value);

    if (device != null) {
      Log.i("Setting webrtc output to: ${device.label}  (${device.deviceId})");
      webrtc.Helper.selectAudioOutput(device.deviceId);
    }
  }
}
