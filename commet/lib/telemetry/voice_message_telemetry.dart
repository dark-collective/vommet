// Vommet telemetry schema v45: voice messages (voice_message). Which step of
// recording, sending or playing one failed: a tester's voice messages didn't
// play on desktop and nothing showed which step. Only enums, numbers, a mime
// type and error type names: never a file name, path, URI, mxc or room/event
// ID, transcript or error message.

import 'dart:async';

import 'package:commet/cache/file_provider.dart';
import 'package:commet/client/matrix/matrix_mxc_file_provider.dart';
import 'package:commet/telemetry/telemetry.dart';
import 'package:commet/telemetry/telemetry_errors.dart';
import 'package:commet/utils/voice_message.dart';

class VoiceMessageTelemetry {
  /// Test seams: whether telemetry is on and where voice_message goes.
  static bool Function() enabled = () => Telemetry.enabled;
  static void Function(String event, Map<String, Object?> fields) record =
      Telemetry.record;

  /// How long playback may take to start before it counts as no_start.
  static Duration noStartAfter = const Duration(seconds: 5);

  /// How long resolve() (cache lookup, download, private copy) plus the
  /// player's open may take before the load counts as stalled: a load that
  /// never finishes (the play button spinning forever) is recorded too,
  /// with the step it hung in (resolve_stalled / open_stalled).
  static Duration stallAfter = const Duration(seconds: 15);

  static final _mime = RegExp(r"^[a-z]{1,16}/[a-z0-9][a-z0-9.+-]{0,63}$");

  static void _send(Map<String, Object?> fields) {
    if (enabled()) record("voice_message", fields);
  }

  static String format(VoiceFormat format) => switch (format) {
        VoiceFormat.oggOpus => "ogg_opus",
        VoiceFormat.aacMp4 => "aac_mp4",
      };

  /// A mime type without its parameters, or null when it doesn't fit the
  /// schema's mime pattern.
  static String? mime(String? mimeType) {
    final m = mimeType?.split(";").first.trim().toLowerCase();
    return m != null && _mime.hasMatch(m) ? m : null;
  }

  /// op=record: [recording] is what the recorder returned (null: nothing).
  static Map<String, Object?> recordFields({
    required bool hold,
    required String outcome,
    String? reason,
    int? startMs,
    VoiceRecording? recording,
    Duration? elapsed,
  }) {
    final waveform = recording?.waveform;
    return {
      "op": "record",
      "outcome": outcome,
      if (reason != null) "reason": reason,
      "mode": hold ? "hold" : "tap",
      if (startMs != null) "start_ms": startMs,
      if (recording != null) ...{
        "duration_ms": recording.duration.inMilliseconds,
        "bytes": recording.bytes.length,
        "format": format(recording.format),
        "level_peak": waveform == null || waveform.isEmpty
            ? 0
            : waveform.reduce((a, b) => a > b ? a : b).clamp(0, 1024),
      } else if (elapsed != null)
        "duration_ms": elapsed.inMilliseconds,
    };
  }

  static void recorded({
    required bool hold,
    required String outcome,
    String? reason,
    int? startMs,
    VoiceRecording? recording,
    Duration? elapsed,
  }) {
    if (!enabled()) return;
    _send(recordFields(
        hold: hold,
        outcome: outcome,
        reason: reason,
        startMs: startMs,
        recording: recording,
        elapsed: elapsed));
  }

  /// op=send. [noRoom]: the room wasn't found for the sending account.
  static Map<String, Object?> sendFields({
    required int ms,
    required int bytes,
    bool? encrypted,
    Object? error,
    bool noRoom = false,
  }) {
    if (noRoom) {
      return {
        "op": "send",
        "outcome": "error",
        "reason": "no_room",
        "bytes": bytes,
      };
    }
    return {
      "op": "send",
      "ms": ms,
      "bytes": bytes,
      if (encrypted != null) "encrypted": encrypted,
      ...Telemetry.errorFields(error),
      if (error != null) "reason": "send_failed",
    };
  }

  static void sent({
    required int ms,
    required int bytes,
    bool? encrypted,
    Object? error,
    bool noRoom = false,
  }) {
    if (!enabled()) return;
    _send(sendFields(
        ms: ms,
        bytes: bytes,
        encrypted: encrypted,
        error: error,
        noRoom: noRoom));
  }

  /// A play attempt for [file], or null with telemetry off (no work then).
  static VoicePlayAttempt? startPlay(FileProvider file, {required bool retry}) {
    if (!enabled()) return null;
    final mxc = file is MxcFileProvider ? file : null;
    return VoicePlayAttempt(
        retry: retry,
        encrypted: mxc?.sensitive,
        mime: mime(mxc?.event?.attachmentMimetype));
  }
}

/// One load of a voice message player (first play or a retry). Records one
/// voice_message op=play once the outcome is known.
class VoicePlayAttempt {
  VoicePlayAttempt({required this.retry, this.encrypted, this.mime}) {
    _stall = Timer(VoiceMessageTelemetry.stallAfter, () {
      if (openMs != null) return;
      _finish(fields(
          outcome: "error",
          reason: resolveMs == null ? "resolve_stalled" : "open_stalled"));
    });
  }

  final bool retry;
  final bool? encrypted;
  final String? mime;

  final Stopwatch _clock = Stopwatch()..start();
  int? resolveMs;
  int? openMs;
  int? _playAt;
  Timer? _noStart;
  Timer? _stall;
  bool done = false;

  void resolved() => resolveMs = _clock.elapsedMilliseconds;

  void opened() {
    openMs = _clock.elapsedMilliseconds - (resolveMs ?? 0);
    _stall?.cancel();
    _stall = null;
  }

  Map<String, Object?> fields(
      {required String outcome,
      String? reason,
      int? startMs,
      Duration? media,
      Object? error}) {
    return {
      "op": "play",
      "outcome": outcome,
      if (reason != null) "reason": reason,
      if (resolveMs != null) "resolve_ms": resolveMs,
      if (openMs != null) "open_ms": openMs,
      if (startMs != null) "start_ms": startMs,
      if (media != null && media > Duration.zero)
        "media_ms": media.inMilliseconds,
      if (encrypted != null) "encrypted": encrypted,
      if (mime != null) "mime": mime,
      "retry": retry,
      if (error != null) "error_type": TelemetryErrors.typeName(error),
    };
  }

  void _finish(Map<String, Object?> fields) {
    if (done) return;
    done = true;
    _cancelTimers();
    VoiceMessageTelemetry._send(fields);
  }

  /// The load failed: resolve_failed, open_failed or play_failed.
  void failed(String reason, {Object? error}) =>
      _finish(fields(outcome: "error", reason: reason, error: error));

  /// The resolve (download) or the player's open threw.
  void loadFailed(Object error) =>
      failed(resolveMs == null ? "resolve_failed" : "open_failed",
          error: error);

  /// play() is about to be called. [media] reads the player's duration
  /// when the no_start timer fires.
  void playCalled({required Duration? Function() media}) {
    if (done) return;
    _playAt = _clock.elapsedMilliseconds;
    _noStart = Timer(
        VoiceMessageTelemetry.noStartAfter,
        () => _finish(
            fields(outcome: "error", reason: "no_start", media: media())));
  }

  /// The position moved past 0: ok. (media_kit's `playing` alone isn't
  /// enough: it mirrors mpv's pause flag, true right after play().)
  void progressed({Duration? media}) {
    final at = _playAt;
    if (at == null || done) return;
    _finish(fields(
        outcome: "ok", startMs: _clock.elapsedMilliseconds - at, media: media));
  }

  /// Paused before the position moved: the outcome is unknown, so nothing
  /// is recorded (no false no_start).
  void paused() {
    if (_playAt != null && !done) dispose();
  }

  /// The widget went away before an outcome: nothing is recorded.
  void dispose() {
    done = true;
    _cancelTimers();
  }

  void _cancelTimers() {
    _noStart?.cancel();
    _noStart = null;
    _stall?.cancel();
    _stall = null;
  }
}
