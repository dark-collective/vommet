// Microphone capture check (#78), shared by the integration test
// (smoke/capture_loopback_test.dart) and the release-build probe
// (capture_probe.dart). No test framework here, so the probe can run in a
// release build: those leave out dev-dependency plugins like integration_test.
//
// The harness feeds a speech-like warble (a steady tone would be removed by
// the noise suppression the app enables) into a virtual microphone
// (PulseAudio null sink on Linux, VB-CABLE on Windows; .vommet/it/capture-*).
// The app opens the microphone through its own code path
// (WebrtcDefaultDevices, so with the shipped voice filter settings) and sends
// it through a pair of local peer connections. The receiver's playout stays
// muted while the level is measured: on Windows it would go to the same cable
// and loop back into the microphone. So the level is the sender's
// (media-source: what goes to the encoder, after the voice filter). A muted
// phase is the control: with the microphone track disabled and the playout
// back on, the receiver must then hear (near) silence.

import 'dart:io';
import 'dart:math';

import 'package:commet/client/components/voip/voice_filter.dart';
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

/// Audio energy and packets so far of the [type] stats (inbound-rtp on the
/// receiver, media-source on the sender, which has no packet count).
Future<({double energy, double duration, int packets})> _audio(
    RTCPeerConnection pc, String type) async {
  for (final r in await pc.getStats()) {
    if (r.type == type && r.values["kind"] == "audio") {
      return (
        energy: (r.values["totalAudioEnergy"] as num?)?.toDouble() ?? 0,
        duration: (r.values["totalSamplesDuration"] as num?)?.toDouble() ?? 0,
        packets: (r.values["packetsReceived"] as num?)?.toInt() ?? 0,
      );
    }
  }
  return (energy: 0.0, duration: 0.0, packets: 0);
}

/// Audio level (RMS, 0..1) of the [type] stats over [seconds]: the loudest
/// 1-second window (speech has pauses, which dilute a plain average), and
/// whether packets kept arriving (inbound-rtp only).
Future<({double level, bool packets})> _measure(
    RTCPeerConnection pc, int seconds, String type) async {
  final first = await _audio(pc, type);
  var prev = first;
  var loudest = 0.0;
  for (var i = 0; i < seconds; i++) {
    await Future.delayed(const Duration(seconds: 1));
    final cur = await _audio(pc, type);
    final dt = cur.duration - prev.duration;
    final de = cur.energy - prev.energy;
    // totalAudioEnergy integrates level^2 over time.
    if (dt > 0 && de > 0) loudest = max(loudest, sqrt(de / dt));
    prev = cur;
  }
  captureLog("$type packets ${first.packets}->${prev.packets} "
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
    Future<void> playout(bool on) async {
      for (final r in await receiver.getReceivers()) {
        r.track?.enabled = on;
      }
    }

    await sender.addTrack(track, mic);
    final offer = await sender.createOffer({});
    await sender.setLocalDescription(offer);
    // The receiver's track would otherwise carry the microphone track's id,
    // and the plugin looks ids up among local tracks first: disabling the
    // playout would disable the microphone instead.
    final id = track.id ?? "";
    await receiver.setRemoteDescription(RTCSessionDescription(
        id.isEmpty ? offer.sdp : offer.sdp?.replaceAll(id, "rx$id"),
        offer.type));
    final answer = await receiver.createAnswer({});
    await receiver.setLocalDescription(answer);
    await sender.setRemoteDescription(answer);
    // Only once the plugin has registered the remote track (on WebRTC's
    // signaling thread): a lookup racing that registration crashed the
    // Windows probe.
    await Future.delayed(const Duration(seconds: 1));
    await playout(false);

    // Let the connection and the capture settle.
    await Future.delayed(const Duration(seconds: 3));

    final live = await _measure(sender, 5, "media-source");
    captureLog("level with signal: ${live.level.toStringAsFixed(4)}");
    captureLog("voice filter: ${VoiceFilter.describeStats()}");
    final arriving = await _measure(receiver, 1, "inbound-rtp");
    if (!arriving.packets) return "no audio packets arrived";

    track.enabled = false;
    await playout(true);
    await Future.delayed(const Duration(seconds: 1));
    // A disabled track may stop sending packets altogether (seen on Linux).
    final muted = await _measure(receiver, 4, "inbound-rtp");
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
