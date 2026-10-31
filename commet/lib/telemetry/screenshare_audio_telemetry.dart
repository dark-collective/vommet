// Vommet: telemetry for the audio a screen share carries (schema v25). One
// `screenshare_audio` event per share, a few seconds after it starts: which
// audio was picked, what the picker could offer, and what the Linux capture
// actually recorded (from our flutter-webrtc fork's counters).
//
// Prompted by a Linux share where the picker offered no apps, "All apps"
// carried the sharer's own voice and none of the video's sound. Only counts,
// durations and fixed words leave the device: never app names, binaries or
// device names.

import 'package:commet/client/components/voip/screen_share_audio.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/telemetry/telemetry.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class ScreenShareAudioTelemetry {
  /// How long after the share starts the capture counters are read.
  static const sampleDelay = Duration(seconds: 10);

  /// Records the event for a share that just started. Not awaited by the
  /// caller; never throws.
  static Future<void> recordShare(
      {required ScreenShareAudio audio,
      required bool audioTrack,
      required bool wayland}) async {
    if (!Telemetry.enabled) return;
    try {
      List<Map<String, dynamic>>? sources;
      try {
        sources = await Helper.getLoopbackAudioSources();
      } catch (_) {
        sources = null;
      }
      await Future.delayed(sampleDelay);
      Map<String, dynamic> stats = const {};
      if (PlatformUtils.isLinux) {
        try {
          stats = await Helper.getLoopbackCaptureStats();
        } catch (_) {}
      }
      Telemetry.record(
          "screenshare_audio",
          fields(
              audio: audio,
              audioTrack: audioTrack,
              wayland: wayland,
              sources: sources,
              stats: stats,
              afterMs: sampleDelay.inMilliseconds));
    } catch (e, s) {
      Log.onError(e, s, content: "Could not record screen share audio");
    }
  }

  /// The event's fields. [sources] is the fork's playback-stream list at
  /// share start (null when listing failed); [stats] its capture counters.
  static Map<String, dynamic> fields({
    required ScreenShareAudio audio,
    required bool audioTrack,
    required bool wayland,
    required List<Map<String, dynamic>>? sources,
    required Map<String, dynamic> stats,
    int? afterMs,
  }) {
    int? count(String key) => switch (stats[key]) {
          final int v => v,
          final num v => v.toInt(),
          _ => null,
        };
    final server = stats["server"];
    return {
      "mode": audio.kind.name,
      if (audio.kind == ScreenShareAudioKind.app)
        "app_id":
            audio.prop == "application.process.binary" ? "binary" : "name",
      "audio_track": audioTrack,
      "wayland": wayland,
      "list_outcome": sources == null ? "error" : "ok",
      if (sources != null) ...{
        "sources": sources.length,
        "sources_self": sources.where((s) => s['isSelf'] == true).length,
        "apps_listed": ScreenShareAudio.appsFrom(sources).length,
      },
      if (stats["available"] == true) ...{
        "capture_running": stats["running"] == true,
        "server":
            server == "pipewire" || server == "pulseaudio" ? server : "unknown",
        "streams_seen": count("streamsSeen"),
        "streams_self": count("streamsSelf"),
        "streams_excluded": count("streamsExcluded"),
        "streams_matched": count("streamsMatched"),
        "streams_virtual": count("streamsVirtual"),
        "streams_on_monitor": count("streamsOnMonitor"),
        "streams_on_other": count("streamsOnOther"),
        "streams_failed": count("streamsFailed"),
        "ms_mixed": count("msMixed"),
        "ms_with_input": count("msWithInput"),
        "ms_audible": count("msAudible"),
      },
      "after_ms": afterMs,
    };
  }
}
