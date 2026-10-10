// End-to-end check of the noise suppression capture filter, without a
// homeserver.
//
// The microphone is whatever PulseAudio source is the default; the remote
// side of a local peer-connection pair plays to the default sink. Run it with
// run_voice_filter_test.sh next to this file, which points both at null sinks,
// plays a noisy clip into the "microphone" and records what came out of each
// phase.
//
// All phases share one call and swap the microphone track. Closing the last
// peer connection makes libwebrtc terminate its audio device, and on Linux
// the next call's PulseAudio streams then fail to start; the app avoids that
// by holding a dummy connection open (WebrtcDefaultDevices.initDummyConnection).
import 'dart:io';

import 'package:commet/client/components/voip/voice_filter.dart';
import 'package:commet/rust/frb_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:integration_test/integration_test.dart';

const phaseSeconds = 10;

Future<void> record(String sink, String path) async {
  final parec = await Process.start('parec', [
    '-d',
    '$sink.monitor',
    '--format=s16le',
    '--rate=48000',
    '--channels=1',
    '--file-format=wav',
    path,
  ]);
  await Future.delayed(const Duration(seconds: phaseSeconds));
  parec.kill(ProcessSignal.sigint);
  await parec.exitCode;
}

/// Opens the microphone the way the app does for [mode] (WebRTC's own
/// suppressor only when ours is off).
Future<MediaStream> openMic(String mode) =>
    navigator.mediaDevices.getUserMedia({
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': mode == "off",
        'autoGainControl': false,
      },
    });

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('noise suppression runs on the microphone inside libwebrtc',
      (tester) async {
    final out = Platform.environment['VOICE_FILTER_OUT'] ?? '/tmp';
    final sink = Platform.environment['VOICE_FILTER_SINK'] ?? 'out';
    await RustLib.init();
    // Load and install the filter up front (it starts off), so every phase
    // can read its counters.
    await VoiceFilter.apply(mode: "standard", experimentEnabled: true);
    await VoiceFilter.apply(mode: "off", experimentEnabled: true);

    final sender = await createPeerConnection({});
    final receiver = await createPeerConnection({});
    sender.onIceCandidate = (c) => receiver.addCandidate(c);
    receiver.onIceCandidate = (c) => sender.addCandidate(c);

    final mics = [await openMic("off")];
    final rtpSender =
        await sender.addTrack(mics.first.getAudioTracks().first, mics.first);
    final offer = await sender.createOffer({});
    await sender.setLocalDescription(offer);
    await receiver.setRemoteDescription(offer);
    final answer = await receiver.createAnswer({});
    await receiver.setLocalDescription(answer);
    await sender.setRemoteDescription(answer);

    Future<VoiceFilterStats> phase(String mode, String file) async {
      await VoiceFilter.apply(mode: mode, experimentEnabled: true);
      if (mode != "off") {
        final mic = await openMic(mode);
        mics.add(mic);
        await rtpSender.replaceTrack(mic.getAudioTracks().first);
      }
      // Let the call settle (and, for "best", give DeepFilterNet3 time to
      // load in the background; RNNoise covers the gap).
      await Future.delayed(const Duration(seconds: 3));
      final before = VoiceFilter.stats()!;
      await record(sink, '$out/$file');
      final after = VoiceFilter.stats()!;
      // ignore: avoid_print
      print('voice filter ($mode): ${VoiceFilter.describeStats()}');
      final processed = after.framesProcessed - before.framesProcessed;
      if (mode == "off") {
        expect(processed, 0);
      } else {
        expect(after.lastSampleRate, 48000);
        // 10 s of 10 ms blocks, minus slack.
        expect(processed > phaseSeconds * 90, isTrue,
            reason: '$processed blocks processed');
      }
      return after;
    }

    await phase("off", 'phase1_basic.wav');
    final standard = await phase("standard", 'phase2_standard.wav');
    final best = await phase("best", 'phase3_best.wav');
    await VoiceFilter.apply(mode: "off", experimentEnabled: true);

    expect(standard.engine, 1, reason: 'standard should run RNNoise');
    expect(best.engine, 2, reason: 'best should run DeepFilterNet3');
    expect(best.demoted, isFalse);

    await sender.close();
    await receiver.close();
    for (final mic in mics) {
      await mic.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
