import 'dart:math';

/// Vommet: whether your own microphone is picking you up, from WebRTC's
/// media-source stats, so your row in the sidebar lights up the moment you
/// speak, even in a whisper (as on Discord).
///
/// LiveKit's active speakers come from the server and need a louder voice,
/// so a whisper others could hear left your own row dark.
///
/// Feed it the running `totalAudioEnergy` and `totalSamplesDuration` of the
/// microphone's media source; it averages the level over each interval
/// between two readings.
class LocalVoiceLevel {
  /// Average level that counts as speaking: about -46 dBFS, above the floor
  /// left after noise suppression and below a whisper.
  static const double threshold = 0.005;

  double? _energy;
  double? _duration;

  /// Takes a new reading; returns whether you were speaking since the last
  /// one, or null when there's nothing to compare yet.
  bool? update(num? totalAudioEnergy, num? totalSamplesDuration) {
    if (totalAudioEnergy == null || totalSamplesDuration == null) {
      reset();
      return null;
    }
    final energy = totalAudioEnergy.toDouble();
    final duration = totalSamplesDuration.toDouble();
    final lastEnergy = _energy;
    final lastDuration = _duration;
    _energy = energy;
    _duration = duration;
    if (lastEnergy == null || lastDuration == null) return null;

    final dt = duration - lastDuration;
    final de = energy - lastEnergy;
    // A new track restarts the counters.
    if (dt <= 0 || de < 0) return null;
    return sqrt(de / dt) >= threshold;
  }

  void reset() {
    _energy = null;
    _duration = null;
  }
}
