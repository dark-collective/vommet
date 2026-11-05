// Telemetry for capture (microphone, camera, screen) start-up: whether it
// worked, how long it took and what kind of device it used (#78). Capture is
// mostly native, platform-specific code (WASAPI, PipeWire, MediaProjection), so
// these events are how a Windows-only regression shows up.
//
// Device labels never leave the device: they can be personal ("Alice's
// AirPods"). A label is only reduced to a fixed device type here, and error
// messages are only read here to pick a fixed error kind.

import 'package:collection/collection.dart';
import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/client/components/voip/voip_stream.dart';
import 'package:commet/client/components/voip/webrtc_default_devices.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/main.dart';
import 'package:commet/telemetry/telemetry.dart';
import 'package:commet/telemetry/telemetry_errors.dart';

class CaptureTelemetry {
  /// A fixed device category from a device label, or "unknown".
  static String deviceType(String? label) {
    if (label == null || label.isEmpty) return "unknown";
    final l = label.toLowerCase();
    if (l.contains("bluetooth") ||
        l.contains("hands-free") ||
        l.contains("handsfree") ||
        l.contains("airpods") ||
        l.contains("bluez")) {
      return "bluetooth";
    }
    if (l.contains("virtual") ||
        l.contains("vb-audio") ||
        l.contains("voicemeeter") ||
        l.contains("cable output") ||
        l.contains("monitor of") ||
        l.contains("steam streaming") ||
        l.contains("broadcast") ||
        l.contains("null")) {
      return "virtual";
    }
    if (l.contains("usb")) return "usb";
    if (l.contains("hdmi") || l.contains("displayport")) return "hdmi";
    if (l.contains("built-in") ||
        l.contains("internal") ||
        l.contains("realtek") ||
        l.contains("array") ||
        l.contains("conexant") ||
        l.contains("sof-hda") ||
        l.contains("hda intel")) {
      return "builtin";
    }
    return "unknown";
  }

  /// error_kind for a capture failure. Platform errors (PlatformException,
  /// LiveKit's TrackCreateException) carry their reason only in the message,
  /// which is read here and reduced to a fixed kind; it is never recorded.
  static String errorKind(Object error) {
    final kind = TelemetryErrors.kind(error);
    if (kind != "unknown") return kind;
    final m = error.toString().toLowerCase();
    if (m.contains("permission") ||
        m.contains("notallowed") ||
        m.contains("denied")) {
      return "permission";
    }
    if (m.contains("notfound") ||
        m.contains("not found") ||
        m.contains("no device") ||
        m.contains("overconstrained")) {
      return "not_found";
    }
    if (m.contains("notreadable") ||
        m.contains("in use") ||
        m.contains("busy") ||
        m.contains("could not start")) {
      return "device_busy";
    }
    return "unknown";
  }

  /// Which microphone capture uses, for the device fields: the one picked in
  /// settings if it is still there, else the system default (the first
  /// input). Read-only: capture itself picks its device elsewhere.
  static Future<({String choice, String? label, int? devices})>
      microphoneChoice() async {
    if (PlatformUtils.isAndroid || PlatformUtils.isWeb) {
      return (choice: "default", label: null, devices: null);
    }
    try {
      final inputs = (await WebrtcDefaultDevices.getDevices())
          .where((d) => d.kind == "audioinput")
          .toList();
      final wanted = preferences.voipDefaultAudioInput.value;
      final picked = inputs.firstWhereOrNull((d) => d.label == wanted);
      return (
        choice: wanted == null
            ? "default"
            : picked == null
                ? "preferred_missing"
                : "preferred",
        label: picked?.label ?? inputs.firstOrNull?.label,
        devices: inputs.length,
      );
    } catch (e) {
      record(source: "mic", action: "enumerate", api: "webrtc", error: e);
      return (choice: "default", label: null, devices: null);
    }
  }

  /// Records whether [session] starts publishing its microphone within
  /// [timeout] of joining. The call backends start the microphone without
  /// waiting for it, so its failure would otherwise only show up as a crash
  /// event (with the error's type) and never as a rate. Nothing is recorded
  /// when the session ends first.
  static Future<void> recordMicrophoneStart(VoipSession session,
      {required String api,
      Duration timeout = const Duration(seconds: 15)}) async {
    if (!Telemetry.enabled) return;
    final clock = Stopwatch()..start();
    bool published() => session.streams.any((s) =>
        s.type == VoipStreamType.audio &&
        s.direction == VoipStreamDirection.outgoing);
    while (!published() && clock.elapsed < timeout) {
      if (session.state == VoipState.ended) return;
      await Future.delayed(const Duration(milliseconds: 250));
    }
    final ok = published();
    final ms = clock.elapsedMilliseconds;
    final mic = await microphoneChoice();
    Telemetry.record("capture", {
      "source": "mic",
      "action": "start",
      "api": api,
      "device_choice": mic.choice,
      "device_type": deviceType(mic.label),
      "devices": mic.devices,
      "ms": ms,
      "outcome": ok ? "ok" : "error",
      if (!ok) "error_kind": "timeout",
    });
  }

  static void record({
    required String source,
    required String action,
    String? api,
    String? deviceChoice,
    String? deviceLabel,
    int? devices,
    int? ms,
    Object? error,
  }) {
    Telemetry.record("capture", {
      "source": source,
      "action": action,
      "api": api,
      "device_choice": deviceChoice,
      "device_type": deviceLabel == null && deviceChoice == null
          ? null
          : deviceType(deviceLabel),
      "devices": devices,
      "ms": ms,
      if (error == null) "outcome": "ok",
      if (error != null) ...{
        "outcome": "error",
        "error_kind": errorKind(error),
        "error_type": TelemetryErrors.typeName(error),
      },
    });
  }

  /// Runs [start], recording a `capture` event with its duration and outcome.
  /// Rethrows, so callers keep their own error handling.
  static Future<T> track<T>(
    Future<T> Function() start, {
    required String source,
    String action = "start",
    String? api,
    String? deviceChoice,
    String? deviceLabel,
    int? devices,
    bool recordSuccess = true,
  }) async {
    final clock = Stopwatch()..start();
    try {
      final result = await start();
      if (recordSuccess) {
        record(
            source: source,
            action: action,
            api: api,
            deviceChoice: deviceChoice,
            deviceLabel: deviceLabel,
            devices: devices,
            ms: clock.elapsedMilliseconds);
      }
      return result;
    } catch (e) {
      record(
          source: source,
          action: action,
          api: api,
          deviceChoice: deviceChoice,
          deviceLabel: deviceLabel,
          devices: devices,
          ms: clock.elapsedMilliseconds,
          error: e);
      rethrow;
    }
  }
}
