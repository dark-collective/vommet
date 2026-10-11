import 'package:commet/utils/voice_message.dart';
import 'package:test/test.dart';

void main() {
  group("levelFromDbfs", () {
    test("full scale is the maximum", () {
      expect(VoiceMessage.levelFromDbfs(0), VoiceMessage.waveformMax);
    });
    test("at or below the floor is zero", () {
      expect(VoiceMessage.levelFromDbfs(-60), 0);
      expect(VoiceMessage.levelFromDbfs(-160), 0);
      expect(VoiceMessage.levelFromDbfs(double.nan), 0);
    });
    test("halfway in dB is half the range", () {
      expect(VoiceMessage.levelFromDbfs(-30), 512);
    });
    test("positive values are clamped", () {
      expect(VoiceMessage.levelFromDbfs(3), VoiceMessage.waveformMax);
    });
  });

  group("resample", () {
    test("averages buckets when shrinking", () {
      expect(VoiceMessage.resample([0, 10, 20, 30], 2), [5, 25]);
    });
    test("repeats values when growing", () {
      expect(VoiceMessage.resample([0, 100], 4), [0, 0, 100, 100]);
    });
    test("same length is a copy, empty stays empty", () {
      expect(VoiceMessage.resample([1, 2, 3], 3), [1, 2, 3]);
      expect(VoiceMessage.resample([], 5), isEmpty);
      expect(VoiceMessage.resample([1], 0), isEmpty);
    });
    test("uneven buckets cover every sample", () {
      final out = VoiceMessage.resample(List.generate(250, (i) => i), 100);
      expect(out.length, 100);
      expect(out.first, lessThanOrEqualTo(2));
      expect(out.last, greaterThanOrEqualTo(247));
    });
  });

  test("waveformFromDbfs caps at sentBars and keeps short recordings as-is",
      () {
    expect(VoiceMessage.waveformFromDbfs([-60, -30, 0]), [0, 512, 1024]);
    expect(VoiceMessage.waveformFromDbfs(List.filled(1000, -30.0)).length,
        VoiceMessage.sentBars);
  });

  test("extraContent has the MSC3245/MSC1767 shape", () {
    final c = VoiceMessage.extraContent(
        const Duration(milliseconds: 4321), [1, 2, 3]);
    expect(c["org.matrix.msc3245.voice"], isEmpty);
    expect(c["org.matrix.msc1767.audio"], {
      "duration": 4321,
      "waveform": [1, 2, 3]
    });
    expect(c["org.matrix.msc1767.text"], "Voice message");
  });

  group("parse", () {
    test("reads an Element-style voice message", () {
      final info = VoiceMessage.parse({
        "msgtype": "m.audio",
        "info": {"duration": 999},
        "org.matrix.msc3245.voice": {},
        "org.matrix.msc1767.audio": {
          "duration": 5200,
          "waveform": [0, 512.4, 2000, -5, "x"]
        },
      })!;
      expect(info.isVoice, isTrue);
      expect(info.duration, const Duration(milliseconds: 5200));
      expect(info.waveform, [0, 512, 1024, 0]);
    });
    test("falls back to info.duration", () {
      final info = VoiceMessage.parse({
        "org.matrix.msc3245.voice": {},
        "info": {"duration": 1500},
      })!;
      expect(info.duration, const Duration(milliseconds: 1500));
      expect(info.waveform, isNull);
    });
    test("plain audio files are not voice messages", () {
      expect(VoiceMessage.parse({"msgtype": "m.audio", "info": {}}), isNull);
    });
    test("audio metadata without the voice flag is parsed but not voice", () {
      final info = VoiceMessage.parse({
        "org.matrix.msc1767.audio": {"duration": 10}
      })!;
      expect(info.isVoice, isFalse);
    });
  });

  test("formatDuration", () {
    expect(VoiceMessage.formatDuration(const Duration(seconds: 7)), "0:07");
    expect(VoiceMessage.formatDuration(const Duration(seconds: 65)), "1:05");
    expect(
        VoiceMessage.formatDuration(const Duration(seconds: 3723)), "1:02:03");
  });

  group("VoiceFormat.choose", () {
    test("Android 10+ records Ogg/Opus, older Android AAC", () {
      expect(VoiceFormat.choose(android: true, linux: false, androidSdk: 29),
          VoiceFormat.oggOpus);
      expect(VoiceFormat.choose(android: true, linux: false, androidSdk: 28),
          VoiceFormat.aacMp4);
    });
    test("Linux records Ogg/Opus, Windows AAC", () {
      expect(
          VoiceFormat.choose(android: false, linux: true), VoiceFormat.oggOpus);
      expect(
          VoiceFormat.choose(android: false, linux: false), VoiceFormat.aacMp4);
    });
    test("mime types and extensions", () {
      expect(VoiceFormat.oggOpus.mimeType, "audio/ogg");
      expect(VoiceFormat.aacMp4.extension, "m4a");
    });
  });
}
