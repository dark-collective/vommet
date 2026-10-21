import 'package:commet/utils/mime.dart';
import 'package:flutter/material.dart';
import 'package:test/test.dart';

void main() {
  group("essence", () {
    test("drops parameters and lower-cases", () {
      expect(Mime.essence("audio/ogg; codecs=opus"), "audio/ogg");
      expect(Mime.essence("Audio/MP4;codecs=mp4a.40.2"), "audio/mp4");
      expect(Mime.essence(" audio/mpeg "), "audio/mpeg");
    });

    test("null and empty stay null", () {
      expect(Mime.essence(null), isNull);
      expect(Mime.essence(""), isNull);
      expect(Mime.essence("; codecs=opus"), isNull);
    });
  });

  group("isPlayableAudio", () {
    test("plain playable types", () {
      expect(Mime.isPlayableAudio("audio/ogg"), isTrue);
      expect(Mime.isPlayableAudio("audio/opus"), isTrue);
      expect(Mime.isPlayableAudio("audio/mp4"), isTrue);
      expect(Mime.isPlayableAudio("audio/x-m4a"), isTrue);
    });

    test("types with parameters", () {
      expect(Mime.isPlayableAudio("audio/ogg; codecs=opus"), isTrue);
      expect(Mime.isPlayableAudio("audio/mp4; codecs=mp4a.40.2"), isTrue);
      expect(Mime.isPlayableAudio("AUDIO/OGG"), isTrue);
    });

    test("generic or missing type falls back to the file name", () {
      for (final name in [
        "voice.opus",
        "VOICE.OPUS",
        "note.m4a",
        "clip.ogg",
        "song.mp3"
      ]) {
        expect(Mime.isPlayableAudio("application/octet-stream", name: name),
            isTrue,
            reason: name);
        expect(Mime.isPlayableAudio(null, name: name), isTrue, reason: name);
      }
    });

    test("generic type without an audio name is not playable", () {
      expect(Mime.isPlayableAudio("application/octet-stream"), isFalse);
      expect(Mime.isPlayableAudio("application/octet-stream", name: "a.zip"),
          isFalse);
      expect(Mime.isPlayableAudio(null, name: "README"), isFalse);
      expect(Mime.isPlayableAudio(null), isFalse);
    });

    test("a specific non-audio type wins over the file name", () {
      expect(
          Mime.isPlayableAudio("application/zip", name: "voice.opus"), isFalse);
      expect(Mime.isPlayableAudio("audio/flac", name: "voice.opus"), isFalse);
    });
  });

  test("toIcon ignores parameters", () {
    expect(Mime.toIcon("audio/ogg; codecs=opus"), Icons.audio_file);
    expect(Mime.toIcon("image/png; charset=binary"), Icons.image);
    expect(Mime.toIcon(null), Icons.file_present);
  });
}
