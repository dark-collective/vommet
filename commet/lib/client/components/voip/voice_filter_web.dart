/// Vommet: web stand-in for voice_filter_native.dart (no native noise
/// suppressor or microphone volume in the browser; the browser's own noise
/// suppression stays on).
class VoiceFilterStats {
  final int framesProcessed;
  final int framesBypassed;
  final int lastSampleRate;
  final int engine;
  final int autoChoice;
  final bool demoted;
  final double dfn3AverageUs;
  final double benchmarkP90Us;

  const VoiceFilterStats(
      this.framesProcessed,
      this.framesBypassed,
      this.lastSampleRate,
      this.engine,
      this.autoChoice,
      this.demoted,
      this.dfn3AverageUs,
      this.benchmarkP90Us);
}

class VoiceFilter {
  static const modes = ["off", "standard", "best", "auto"];

  static bool get isSupported => false;
  static bool get isEnabled => false;
  static bool get useWebrtcNoiseSuppression => true;
  static bool get supportsVolume => false;
  static double get microphoneVolume => 1.0;

  static Future<void> apply({String? mode, bool? experimentEnabled}) async {}

  static VoiceFilterStats? stats() => null;

  static String describeStats() => "not supported on web";
}
