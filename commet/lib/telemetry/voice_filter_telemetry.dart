// Vommet (schema v26): what the microphone noise suppression did during the
// last minute of a call, added to each `call_stats` event. "I tried every
// noise suppression mode and nothing changed" (Windows, 2026-10-16) came with
// nothing in telemetry to say whether the filter was on, installed, or
// skipping the audio. Counts, the processing rate and fixed words only.

import 'package:commet/client/components/voip/voice_filter.dart';
import 'package:commet/main.dart';

class VoiceFilterTelemetry {
  static const engines = ["none", "rnnoise", "dfn3"];

  VoiceFilterStats? _prev;

  /// Remembers the filter's counters, so the first sample of a call only
  /// counts that call's audio.
  void begin() {
    if (VoiceFilter.isSupported) _prev = VoiceFilter.stats();
  }

  /// The fields for this minute; empty where the filter doesn't exist.
  Map<String, Object?> sample() {
    if (!VoiceFilter.isSupported) return const {};
    final now = VoiceFilter.stats();
    final f = fields(
      experiment: VoiceFilter.isEnabled,
      mode: preferences.voipNoiseSuppression.value,
      webrtc: VoiceFilter.useWebrtcNoiseSuppression,
      microphoneVolume: VoiceFilter.microphoneVolume,
      installed: VoiceFilter.installed,
      now: now,
      prev: _prev,
    );
    _prev = now ?? _prev;
    return f;
  }

  static String _engine(int e) =>
      e >= 0 && e < engines.length ? engines[e] : "none";

  static int _delta(int now, int? prev) =>
      (now - (prev ?? 0)).clamp(0, 1000000);

  /// Pure, for unit tests. [now] is null when the native filter was never
  /// loaded (the experiment was never on and the volume never moved).
  static Map<String, Object?> fields({
    required bool experiment,
    required String mode,
    required bool webrtc,
    required double microphoneVolume,
    required bool installed,
    VoiceFilterStats? now,
    VoiceFilterStats? prev,
  }) =>
      {
        "ns_experiment": experiment,
        "ns_mode":
            experiment && VoiceFilter.modes.contains(mode) ? mode : "off",
        "ns_webrtc": webrtc,
        "mic_volume_pct": (microphoneVolume * 100).round().clamp(0, 1000),
        "ns_installed": installed,
        if (now != null) ...{
          "ns_engine": _engine(now.engine),
          "ns_auto": _engine(now.autoChoice),
          "ns_demoted": now.demoted,
          "ns_processed": _delta(now.framesProcessed, prev?.framesProcessed),
          "ns_bypassed": _delta(now.framesBypassed, prev?.framesBypassed),
          "ns_resampled": _delta(now.framesResampled, prev?.framesResampled),
          if (now.lastSampleRate > 0)
            "ns_rate": now.lastSampleRate.clamp(0, 1000000),
          if (now.dfn3AverageUs > 0)
            "ns_dfn3_us": now.dfn3AverageUs.round().clamp(0, 1000000),
          if (now.benchmarkP90Us > 0)
            "ns_bench_us": now.benchmarkP90Us.round().clamp(0, 1000000),
        },
      };
}
