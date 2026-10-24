// Vommet telemetry schema v26: the microphone noise suppression's state and
// what it did, on each call_stats event. Counts, the rate and fixed words.

import 'dart:io';

import 'package:commet/client/components/voip/voice_filter.dart';
import 'package:commet/telemetry/telemetry_schema.dart';
import 'package:commet/telemetry/voice_filter_telemetry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final schema = TelemetrySchema.parse(
      File("assets/telemetry/schema.json").readAsStringSync());

  test("schema is v26", () {
    expect(schema.version, greaterThanOrEqualTo(26));
  });

  Map<String, Object> event(Map<String, Object?> fields) => {
        "e": "call_stats",
        "t": 1000,
        "quality": "excellent",
        for (final e in fields.entries)
          if (e.value != null) e.key: e.value as Object,
      };

  const before = VoiceFilterStats(1000, 5, 48000, 1, 2, false, 0, 900, 0);
  // A minute at 16 kHz on DeepFilterNet3: every block resampled.
  const after =
      VoiceFilterStats(7000, 5, 16000, 2, 2, false, 610.4, 900.2, 6000);

  test("a minute's counters are the change since the last sample", () {
    final f = VoiceFilterTelemetry.fields(
        experiment: true,
        mode: "best",
        webrtc: false,
        microphoneVolume: 1.25,
        installed: true,
        now: after,
        prev: before);
    expect(f["ns_mode"], "best");
    expect(f["ns_engine"], "dfn3");
    expect(f["ns_auto"], "dfn3");
    expect(f["ns_processed"], 6000);
    expect(f["ns_bypassed"], 0);
    expect(f["ns_resampled"], 6000);
    expect(f["ns_rate"], 16000);
    expect(f["ns_dfn3_us"], 610);
    expect(f["ns_bench_us"], 900);
    expect(f["mic_volume_pct"], 125);
    expect(schema.validateEvent(event(f)), isTrue);
  });

  test("with the experiment off the mode reads off, whatever is stored", () {
    final f = VoiceFilterTelemetry.fields(
        experiment: false,
        mode: "best",
        webrtc: true,
        microphoneVolume: 1.0,
        installed: false);
    expect(f["ns_mode"], "off");
    expect(f.containsKey("ns_engine"), isFalse);
    expect(f.containsKey("ns_processed"), isFalse);
    expect(schema.validateEvent(event(f)), isTrue);
  });

  test("first sample without a baseline counts from zero", () {
    final f = VoiceFilterTelemetry.fields(
        experiment: true,
        mode: "standard",
        webrtc: false,
        microphoneVolume: 1.0,
        installed: true,
        now: before);
    expect(f["ns_processed"], 1000);
    expect(f["ns_engine"], "rnnoise");
    expect(f.containsKey("ns_dfn3_us"), isFalse);
    expect(schema.validateEvent(event(f)), isTrue);
  });

  test("unknown words can't ride along", () {
    final ok = event(VoiceFilterTelemetry.fields(
        experiment: true,
        mode: "something new",
        webrtc: false,
        microphoneVolume: 1.0,
        installed: true,
        now: after,
        prev: before));
    expect(ok["ns_mode"], "off");
    expect(schema.validateEvent(ok), isTrue);
    for (final bad in [
      {"ns_mode": "krisp"},
      {"ns_engine": "Krisp"},
      {"ns_rate": "16000"},
      {"ns_processed": -1},
      {"ns_device": "Headset"},
    ]) {
      expect(schema.validateEvent({...ok, ...bad}), isFalse, reason: "$bad");
    }
  });
}
