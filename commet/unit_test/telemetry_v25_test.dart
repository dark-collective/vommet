// Vommet telemetry schema v25: screenshare_audio, the audio a screen share
// carries and what the Linux capture recorded. Counts and fixed words only.

import 'dart:io';

import 'package:commet/client/components/voip/screen_share_audio.dart';
import 'package:commet/telemetry/screenshare_audio_telemetry.dart';
import 'package:commet/telemetry/telemetry_schema.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final schema = TelemetrySchema.parse(
      File("assets/telemetry/schema.json").readAsStringSync());

  test("schema is v25", () {
    expect(schema.version, greaterThanOrEqualTo(25));
  });

  final sources = [
    {"applicationName": "Vommet", "binary": "vommet", "isSelf": true},
    {"applicationName": "Firefox", "binary": "firefox", "isSelf": false},
    {"applicationName": "Firefox", "binary": "firefox", "isSelf": false},
    {"applicationName": "mpv", "binary": "", "isSelf": false},
    {"applicationName": "", "binary": "", "isSelf": false},
  ];

  const stats = {
    "available": true,
    "running": true,
    "server": "pipewire",
    "streamsSeen": 4,
    "streamsSelf": 1,
    "streamsExcluded": 0,
    "streamsMatched": 3,
    "streamsVirtual": 1,
    "streamsOnMonitor": 2,
    "streamsOnOther": 1,
    "streamsFailed": 0,
    "msMixed": 10000,
    "msWithInput": 9800,
    "msAudible": 4200,
  };

  Map<String, Object> event(Map<String, dynamic> fields) => {
        "e": "screenshare_audio",
        "t": 1000,
        for (final e in fields.entries)
          if (e.value != null) e.key: e.value as Object,
      };

  test("the picker's apps: one per program, without Vommet", () {
    final apps = ScreenShareAudio.appsFrom(sources);
    expect(apps.map((a) => a.label), ["Firefox", "mpv"]);
  });

  test("all-apps share with capture counters validates", () {
    final f = ScreenShareAudioTelemetry.fields(
        audio: ScreenShareAudio.system,
        audioTrack: true,
        wayland: true,
        sources: sources,
        stats: stats,
        afterMs: 10000);
    expect(f["mode"], "system");
    expect(f["sources"], 5);
    expect(f["sources_self"], 1);
    expect(f["apps_listed"], 2);
    expect(f["server"], "pipewire");
    expect(f["streams_on_other"], 1);
    expect(f["ms_audible"], 4200);
    expect(schema.validateEvent(event(f)), isTrue);
  });

  test("app share says only whether a binary or a name picked the app", () {
    final f = ScreenShareAudioTelemetry.fields(
        audio: const ScreenShareAudio.app(
            "application.process.binary", "firefox", "Firefox"),
        audioTrack: true,
        wayland: false,
        sources: sources,
        stats: stats);
    expect(f["app_id"], "binary");
    expect(f.values, isNot(contains("firefox")));
    expect(f.values, isNot(contains("Firefox")));
    expect(schema.validateEvent(event(f)), isTrue);
  });

  test("no counters before a capture ran; listing failure is an outcome", () {
    final f = ScreenShareAudioTelemetry.fields(
        audio: ScreenShareAudio.none,
        audioTrack: false,
        wayland: false,
        sources: null,
        stats: const {});
    expect(f["list_outcome"], "error");
    expect(f.containsKey("streams_seen"), isFalse);
    expect(f.containsKey("sources"), isFalse);
    expect(schema.validateEvent(event(f)), isTrue);
  });

  test("unknown server words and app names can't ride along", () {
    final f = ScreenShareAudioTelemetry.fields(
        audio: ScreenShareAudio.system,
        audioTrack: true,
        wayland: false,
        sources: sources,
        stats: {...stats, "server": "PulseAudio (on PipeWire 1.2.7)"});
    expect(f["server"], "unknown");
    final ok = event(f);
    expect(schema.validateEvent(ok), isTrue);
    for (final bad in [
      {"mode": "Firefox"},
      {"app_id": "firefox"},
      {"server": "PulseAudio (on PipeWire 1.2.7)"},
      {"streams_seen": "4"},
      {"app": "firefox"},
    ]) {
      expect(schema.validateEvent({...ok, ...bad}), isFalse, reason: "$bad");
    }
  });
}
