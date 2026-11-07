// Vommet telemetry schema v44: how the microphone started at a MatrixRTC
// call join (call_mic), with the capture event's device fields and error
// kinds. Never an error message or a device name.

import 'dart:async';

import 'package:commet/debug/log.dart';
import 'package:commet/telemetry/capture_telemetry.dart';
import 'package:commet/telemetry/telemetry.dart';
import 'package:commet/telemetry/telemetry_errors.dart';

typedef MicrophoneChoice = ({String choice, String? label, int? devices});

class CallMicTelemetry {
  /// Test seams: whether telemetry is on, where call_mic goes, and which
  /// microphone capture uses.
  static bool Function() enabled = () => Telemetry.enabled;
  static void Function(String event, Map<String, Object?> fields) record =
      Telemetry.record;
  static Future<MicrophoneChoice> Function() microphone =
      CaptureTelemetry.microphoneChoice;

  /// The call_mic mode: a call started muted is "muted" with or without
  /// push to talk (nothing is published then).
  static String modeFor({required bool pushToTalk, required bool muted}) =>
      muted
          ? "muted"
          : pushToTalk
              ? "push_to_talk"
              : "open";

  /// Starts the microphone at a call join and records how it went (not
  /// awaited: the call opens while the microphone starts). With push to talk
  /// it's published muted ([publishMuted], capture kept open for the key);
  /// otherwise it's enabled unless the call starts muted ([setEnabled]). A
  /// null function means there is no local participant to start it on.
  /// Returns the start, or null without a participant.
  static Future<void>? startAtJoin(
      {required bool pushToTalk,
      required bool muted,
      required Future<void> Function()? publishMuted,
      required Future<void> Function(bool enabled)? setEnabled}) {
    final Future<void>? start = pushToTalk
        ? (muted ? Future<void>.value() : publishMuted?.call())
        : setEnabled?.call(!muted);
    unawaited(
        track(start, mode: modeFor(pushToTalk: pushToTalk, muted: muted)));
    return start;
  }

  /// [start] is the microphone start (null: there was no local participant
  /// to start it on).
  static Future<void> track(Future<void>? start, {required String mode}) async {
    // The devices are read after the start (never before it: no extra
    // permission prompt), and only with telemetry on.
    final fields = await measure(start,
        mode: mode,
        microphone: () async => enabled() ? await microphone() : null);
    if (enabled()) record("call_mic", fields);
  }

  /// Waits for [start], logs a failure and returns the call_mic fields.
  static Future<Map<String, Object?>> measure(Future<void>? start,
      {required String mode,
      Future<MicrophoneChoice?> Function()? microphone}) async {
    final clock = Stopwatch()..start();
    Object? error;
    if (start == null) {
      // No local participant to start it on: recorded, not logged as a crash.
      error = StateError("no local participant");
    } else {
      try {
        await start;
      } catch (e, s) {
        error = e;
        Log.onError(e, s,
            content: "Could not start the microphone for the call");
      }
    }
    final ms = clock.elapsedMilliseconds;
    MicrophoneChoice? mic;
    try {
      mic = await microphone?.call();
    } catch (_) {
      // Diagnostics never get in the way of the call.
    }
    return {
      "kind": "matrixrtc",
      "mode": mode,
      "ms": ms,
      if (mic != null) ...{
        "device_choice": mic.choice,
        "device_type": CaptureTelemetry.deviceType(mic.label),
        if (mic.devices != null) "devices": mic.devices,
      },
      if (error == null)
        "outcome": "ok"
      else ...{
        "outcome": "error",
        "error_kind": CaptureTelemetry.errorKind(error),
        "error_type": TelemetryErrors.typeName(error),
      },
    };
  }
}
