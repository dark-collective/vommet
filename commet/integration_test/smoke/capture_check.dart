// Microphone capture check (#78), shared by the integration test
// (smoke/capture_loopback_test.dart) and the release-build probe
// (capture_probe.dart). No test framework here, so the probe can run in a
// release build: those leave out dev-dependency plugins like integration_test.
//
// The harness feeds a speech-like warble (a steady tone would be removed by
// the noise suppression the app enables) into a virtual microphone
// (PulseAudio null sink on Linux, VB-CABLE on Windows; .vommet/it/capture-*).
// The app opens the microphone through its own code path
// (WebrtcDefaultDevices), sends it through a pair of local peer connections,
// and the receiving side's WebRTC stats must show real audio energy. A muted
// phase is the control: the same measurement must then read (near) silence,
// so a pass can't be an artefact.

import 'dart:io';
import 'dart:math';

import 'package:commet/client/components/voip/webrtc_default_devices.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Result lines are also appended to this file when set: the Windows probe
/// has no console, and the harness must see the results.
const _logFile = String.fromEnvironment('CAPTURE_LOG');

void captureLog(String line) {
  // ignore: avoid_print
  print("CAPTURE $line");
  if (_logFile.isNotEmpty) {
    File(_logFile).writeAsStringSync("CAPTURE $line\n", mode: FileMode.append);
  }
}

/// Received audio energy and packets so far (inbound-rtp, audio).
Future<({double energy, double duration, int packets})> _inbound(
    RTCPeerConnection pc) async {
  for (final r in await pc.getStats()) {
    if (r.type == "inbound-rtp" && r.values["kind"] == "audio") {
      return (
        energy: (r.values["totalAudioEnergy"] as num?)?.toDouble() ?? 0,
        duration: (r.values["totalSamplesDuration"] as num?)?.toDouble() ?? 0,
        packets: (r.values["packetsReceived"] as num?)?.toInt() ?? 0,
      );
    }
  }
  return (energy: 0.0, duration: 0.0, packets: 0);
}

/// Audio level (RMS, 0..1) of received audio over [seconds]: the loudest
/// 1-second window (speech has pauses, which dilute a plain average), and
/// whether packets kept arriving.
Future<({double level, bool packets})> _measure(
    RTCPeerConnection pc, int seconds) async {
  final first = await _inbound(pc);
  var prev = first;
  var loudest = 0.0;
  for (var i = 0; i < seconds; i++) {
    await Future.delayed(const Duration(seconds: 1));
    final cur = await _inbound(pc);
    final dt = cur.duration - prev.duration;
    final de = cur.energy - prev.energy;
    // totalAudioEnergy integrates level^2 over time.
    if (dt > 0 && de > 0) loudest = max(loudest, sqrt(de / dt));
    prev = cur;
  }
  captureLog("packets ${first.packets}->${prev.packets} "
      "duration ${(prev.duration - first.duration).toStringAsFixed(2)}s "
      "loudest 1 s window ${loudest.toStringAsFixed(4)}");
  return (level: loudest, packets: prev.packets > first.packets);
}

/// Runs the check; returns null on success, else why it failed. Logs
/// "CAPTURE PASS" on success.
Future<String?> runCaptureCheck() async {
  final devices = (await WebrtcDefaultDevices.getDevices())
      .where((d) => d.kind == "audioinput")
      .toList();
  captureLog("audio inputs: ${devices.length}");
  // CI output only (never telemetry): which devices the app sees.
  for (final d in devices) {
    captureLog("input '${d.label}' id=${d.deviceId}");
  }
  if (devices.isEmpty) return "no audio input devices";

  // The app's own microphone path (settings' device or the default).
  final mic = await WebrtcDefaultDevices.getDefaultMicrophone() ??
      await navigator.mediaDevices.getUserMedia({'audio': true});
  final track = mic.getAudioTracks().first;
  captureLog("capturing '${track.label}' settings=${track.getSettings()}");

  final sender = await createPeerConnection({});
  final receiver = await createPeerConnection({});
  try {
    sender.onIceCandidate = (c) => receiver.addCandidate(c);
    receiver.onIceCandidate = (c) => sender.addCandidate(c);
    await sender.addTrack(track, mic);
    final offer = await sender.createOffer({});
    await sender.setLocalDescription(offer);
    await receiver.setRemoteDescription(offer);
    final answer = await receiver.createAnswer({});
    await receiver.setLocalDescription(answer);
    await sender.setRemoteDescription(answer);

    // Let the connection and the capture settle.
    await Future.delayed(const Duration(seconds: 3));

    final live = await _measure(receiver, 5);
    captureLog("level with signal: ${live.level.toStringAsFixed(4)}");
    if (!live.packets) return "no audio packets arrived";

    track.enabled = false;
    await Future.delayed(const Duration(seconds: 1));
    // A disabled track may stop sending packets altogether (seen on Linux).
    final muted = await _measure(receiver, 4);
    captureLog("level muted: ${muted.level.toStringAsFixed(4)}");

    // A capture that delivers silence measured ~0.00003 (Windows, before the
    // harness played into the cable); real captures read 0.005-0.61 depending
    // on the platform's processing (WebRTC's noise suppression is on, and
    // adapts to steady signals; AGC where libwebrtc ignores the app's
    // autoGainControl: false). 0.002 is ~66x the silent reading.
    if (live.level <= 0.002) return "the microphone sent silence";
    if (muted.level >= live.level / 4) return "muted level isn't lower";
    captureLog("PASS");
    return null;
  } finally {
    await sender.close();
    await receiver.close();
    await mic.dispose();
  }
}
