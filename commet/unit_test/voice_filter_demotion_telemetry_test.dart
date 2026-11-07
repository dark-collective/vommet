// Vommet issue 1148: the sampled fallback category uses the existing opt-in
// call_stats event, never a new event or audio measurement.
import 'package:commet/client/components/voip/voice_filter.dart';
import 'package:commet/telemetry/telemetry_schema.dart';
import 'package:commet/telemetry/voice_filter_telemetry.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('call_stats distinguishes fallback reasons and omits unavailable ones',
      () async {
    final schema = TelemetrySchema.parse(
        await rootBundle.loadString('assets/telemetry/schema.json'));
    Map<String, Object?> fields(VoiceFilterStats? stats) =>
        VoiceFilterTelemetry.fields(
          experiment: true,
          mode: 'best',
          webrtc: false,
          microphoneVolume: 1,
          installed: stats != null,
          now: stats,
        );
    Map<String, Object> event(Map<String, Object?> fields) => {
          'e': 'call_stats',
          't': 60000,
          'quality': 'good',
          for (final entry in fields.entries)
            if (entry.value != null) entry.key: entry.value as Object,
        };

    for (final (reason, expected) in [
      (0, 'none'),
      (1, 'too_slow'),
      (2, 'silent_output'),
    ]) {
      final stats = VoiceFilterStats(
          6000, 0, 16000, 1, 2, reason != 0, 500, 900, 6000, reason);
      final sample = fields(stats);
      expect(sample['ns_demote_reason'], expected);
      expect(sample['ns_demoted'], reason != 0);
      expect(schema.validateEvent(event(sample)), isTrue);
      // State persists across samples; this is not a transition counter.
      expect(fields(stats)['ns_demote_reason'], expected);
    }

    for (final stats in [
      null,
      const VoiceFilterStats(0, 0, 0, 1, 2, true, 0, 0, 0),
      const VoiceFilterStats(0, 0, 0, 1, 2, false, 0, 0, 0, 1),
      const VoiceFilterStats(0, 0, 0, 1, 2, false, 0, 0, 0, 2),
      const VoiceFilterStats(0, 0, 0, 1, 2, true, 0, 0, 0, 3),
      const VoiceFilterStats(0, 0, 0, 1, 2, true, 0, 0, 0, -1),
    ]) {
      final sample = fields(stats);
      expect(sample.containsKey('ns_demote_reason'), isFalse);
      expect(schema.validateEvent(event(sample)), isTrue);
    }

    for (final bad in ['', 'unknown', 'speech heard', 0, 1, 2, true, {}]) {
      expect(schema.validateEvent(event({'ns_demote_reason': bad})), isFalse);
    }
    // The existing boolean and an absent reason remain valid for old data.
    expect(schema.validateEvent(event({'ns_demoted': true})), isTrue);
  });
}
