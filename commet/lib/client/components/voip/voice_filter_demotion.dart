/// The voice filter stats' demotion text: whether the stream fell back from
/// DeepFilterNet3 to RNNoise, and why (`VoiceFilterStats.demoteReason`:
/// 1 too slow, 2 silent output on a speaking input).
String describeDemotion(bool demoted, int reason) =>
    "demoted=$demoted${switch (reason) {
      1 => " (too slow)",
      2 => " (silent output)",
      _ => "",
    }}";
