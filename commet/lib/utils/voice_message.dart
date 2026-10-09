import 'dart:math';
import 'dart:typed_data';

/// Matrix voice messages: an m.audio event marked with MSC3245 and carrying
/// MSC1767 audio metadata (duration in ms, waveform of 0..1024 values), the
/// shape Element, FluffyChat and others send and render as a voice bubble.
class VoiceMessage {
  static const String voiceKey = "org.matrix.msc3245.voice";
  static const String audioKey = "org.matrix.msc1767.audio";
  static const String textKey = "org.matrix.msc1767.text";

  /// Waveform values are integers in 0..[waveformMax].
  static const int waveformMax = 1024;

  /// How many bars a sent waveform carries.
  static const int sentBars = 100;

  /// Quietest level that still shows as a non-zero bar.
  static const double floorDbfs = -60;

  /// Extra event content that turns an m.audio file event into a voice
  /// message. Spread into the content next to msgtype/url/info.
  static Map<String, dynamic> extraContent(
      Duration duration, List<int> waveform) {
    return {
      voiceKey: <String, dynamic>{},
      audioKey: {
        "duration": duration.inMilliseconds,
        "waveform": waveform,
      },
      textKey: "Voice message",
    };
  }

  /// One level sample (dBFS, 0 = full scale, negative = quieter) mapped to
  /// 0..[waveformMax] on a perceptual (dB) scale with a [floorDbfs] floor.
  static int levelFromDbfs(double dbfs) {
    if (dbfs.isNaN) return 0;
    final t = ((dbfs - floorDbfs) / -floorDbfs).clamp(0.0, 1.0);
    return (t * waveformMax).round();
  }

  /// Resample [values] to exactly [count] bars by averaging buckets (or
  /// repeating values when there are fewer samples than bars). Empty in,
  /// empty out.
  static List<int> resample(List<int> values, int count) {
    if (values.isEmpty || count <= 0) return const [];
    if (values.length == count) return List.of(values);
    final out = <int>[];
    for (var i = 0; i < count; i++) {
      final start = (i * values.length / count).floor();
      var end = ((i + 1) * values.length / count).floor();
      if (end <= start) end = start + 1;
      var sum = 0;
      for (var j = start; j < end && j < values.length; j++) {
        sum += values[j];
      }
      out.add((sum / (min(end, values.length) - start)).round());
    }
    return out;
  }

  /// The waveform to send for a recording sampled as [dbfsSamples].
  static List<int> waveformFromDbfs(List<double> dbfsSamples) {
    final levels = dbfsSamples.map(levelFromDbfs).toList();
    return levels.length <= sentBars ? levels : resample(levels, sentBars);
  }

  /// Parses voice-message metadata from event [content], or null when the
  /// event isn't a voice message. Tolerates missing or malformed fields.
  static VoiceMessageInfo? parse(Map<String, dynamic> content) {
    final isVoice = content.containsKey(voiceKey);
    final audio = content[audioKey];
    if (!isVoice && audio is! Map) return null;

    int? durationMs;
    List<int>? waveform;
    if (audio is Map) {
      final d = audio["duration"];
      if (d is num) durationMs = d.round();
      final w = audio["waveform"];
      if (w is List) {
        waveform = [
          for (final v in w)
            if (v is num) v.round().clamp(0, waveformMax)
        ];
      }
    }
    if (durationMs == null) {
      final info = content["info"];
      if (info is Map && info["duration"] is num) {
        durationMs = (info["duration"] as num).round();
      }
    }
    return VoiceMessageInfo(
      isVoice: isVoice,
      duration: durationMs == null ? null : Duration(milliseconds: durationMs),
      waveform: (waveform == null || waveform.isEmpty) ? null : waveform,
    );
  }

  /// "0:07", "1:05", "1:02:03".
  static String formatDuration(Duration d) {
    final s = d.inSeconds;
    final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
    final ss = sec.toString().padLeft(2, "0");
    if (h > 0) return "$h:${m.toString().padLeft(2, "0")}:$ss";
    return "$m:$ss";
  }
}

class VoiceMessageInfo {
  final bool isVoice;
  final Duration? duration;
  final List<int>? waveform;
  const VoiceMessageInfo({required this.isVoice, this.duration, this.waveform});
}

/// Which recording format to use. Ogg/Opus is what voice messages normally
/// use; platforms that can't encode it record AAC in MP4 instead, which every
/// major client also plays.
enum VoiceFormat {
  oggOpus("audio/ogg", "ogg"),
  aacMp4("audio/mp4", "m4a");

  const VoiceFormat(this.mimeType, this.extension);
  final String mimeType;
  final String extension;

  /// Android encodes Opus from API 29 (Android 10); Linux encodes it with
  /// ffmpeg (present in the Flatpak runtime); Windows' recorder has no Opus.
  static VoiceFormat choose(
      {required bool android, required bool linux, int? androidSdk}) {
    if (android) {
      return (androidSdk ?? 0) >= 29 ? oggOpus : aacMp4;
    }
    if (linux) return oggOpus;
    return aacMp4;
  }
}

/// A finished recording, ready to send as a voice message.
class VoiceRecording {
  final Uint8List bytes;
  final VoiceFormat format;
  final Duration duration;

  /// 0..1024 per bar, at most [VoiceMessage.sentBars] bars.
  final List<int> waveform;

  const VoiceRecording({
    required this.bytes,
    required this.format,
    required this.duration,
    required this.waveform,
  });

  String get fileName => "Voice message.${format.extension}";
}
