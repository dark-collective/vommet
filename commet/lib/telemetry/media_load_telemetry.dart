// Vommet (schema v46, Vommet issue 1065): voice messages, videos and files
// that hang while loading. A download was only counted (http_stats) once it
// ended, so one that never answered left nothing behind: on the reporter's
// Android not a single voice or video download was recorded. Each load is
// now watched: still running after [MediaLoadWatch.stallAfter], it records
// one media_load_stall with the step it is in; when it ends, media_load
// with the outcome and the total time. Only the step, times, sizes, the
// kind of file, whether it is encrypted and which media endpoint was used
// are kept: never the URL, the media ID, the room, the user or a file name.
// Watching changes nothing about the load itself (no timeout, no retry).

import 'dart:async';

import 'package:commet/telemetry/telemetry.dart';
import 'package:media_kit/media_kit.dart';

class MediaLoadWatch {
  /// How long a load may run before it counts as stalled. Tests shorten it.
  static Duration stallAfter = const Duration(seconds: 10);

  /// Whether loads are watched at all, and where the events go. Tests
  /// replace them.
  static bool Function() enabled = () => Telemetry.enabled;
  static void Function(String event, Map<String, Object?> fields) record =
      Telemetry.record;

  /// Test seam: called with every new watch, so a test can fire its stall
  /// at a known step instead of racing [stallAfter].
  static void Function(MediaLoadWatch watch)? onCreate;

  /// `resolve` (MxcFileProvider.resolve: download, decrypt, write a copy),
  /// `stream` (a video through MediaStream) or `voice_open` (the player
  /// opening a resolved voice message).
  final String path;

  /// `voice`, `audio`, `video`, `image`, `file` or `unknown`.
  final String kind;

  /// Media from an end-to-end encrypted room (MxcFileProvider.sensitive),
  /// the same meaning on every path and as voice_message's.
  final bool encrypted;

  /// `v1` (authenticated media), `legacy` (/_matrix/media/) or `other`;
  /// null until the request is made.
  String? endpoint;

  /// The file's size: Content-Length, else the event's info.size.
  int? size;
  int bytes = 0;

  /// The answer's HTTP status, sent with an error end (a 404 or 502 is
  /// otherwise only a MediaDownloadException or HttpException).
  int? httpStatus;

  /// `cache` (cache lookup, private copy), `request_sent`, `headers`,
  /// `body`, `decrypting`, `writing` or `opening`.
  String step;

  final Stopwatch _clock = Stopwatch()..start();
  Timer? _timer;
  bool _stalled = false;
  bool _ended = false;

  MediaLoadWatch(
      {required this.path,
      required this.kind,
      required this.encrypted,
      this.size,
      this.step = "cache"}) {
    if (!enabled()) {
      _ended = true;
      return;
    }
    _timer = Timer(stallAfter, _stall);
    onCreate?.call(this);
  }

  /// [MediaLoadWatch] for a Matrix event's content (msgtype, info.size).
  factory MediaLoadWatch.forContent(String path, Map<String, Object?>? content,
      {required bool encrypted, String step = "cache"}) {
    final info = content?["info"];
    final size = info is Map ? info["size"] : null;
    return MediaLoadWatch(
        path: path,
        kind: kindOf(content),
        encrypted: encrypted,
        size: size is int && size > 0 ? size : null,
        step: step);
  }

  static String kindOf(Map<String, Object?>? content) {
    if (content == null) return "unknown";
    if (content.containsKey("org.matrix.msc3245.voice")) return "voice";
    return switch (content["msgtype"]) {
      "m.audio" => "audio",
      "m.video" => "video",
      "m.image" => "image",
      "m.file" => "file",
      _ => "unknown",
    };
  }

  static String endpointOf(Uri url) {
    final path = url.path;
    if (path.contains("/_matrix/client/v1/media/")) return "v1";
    if (path.contains("/_matrix/media/")) return "legacy";
    return "other";
  }

  void request(Uri url) {
    endpoint = endpointOf(url);
    step = "request_sent";
  }

  void headers(int? contentLength, {int? status}) {
    httpStatus = status;
    if (contentLength != null && contentLength >= 0) size = contentLength;
    step = "headers";
  }

  void received(int total) {
    bytes = total;
    step = "body";
  }

  Map<String, Object?> _fields() => {
        "path": path,
        "kind": kind,
        "step": step,
        "encrypted": encrypted,
        "endpoint": endpoint,
        "bytes": bytes,
        "size": size,
      };

  /// What [stallAfter] running out does; tests call it directly.
  void stallNow() => _stall();

  void _stall() {
    if (_ended) return;
    _stalled = true;
    record("media_load_stall", {
      ..._fields(),
      "elapsed_ms": _clock.elapsedMilliseconds,
    });
  }

  /// Records how the load ended (once). [error] null and [ok] true: it
  /// finished; [cancelled]: it was stopped (the player went away).
  void end({bool ok = true, Object? error, bool cancelled = false}) {
    if (_ended) return;
    _ended = true;
    _timer?.cancel();
    record("media_load", {
      ..._fields(),
      "outcome": cancelled
          ? "cancelled"
          : ok && error == null
              ? "ok"
              : "error",
      "stalled": _stalled,
      "total_ms": _clock.elapsedMilliseconds,
      if (error != null && !cancelled) ...Telemetry.errorFields(error),
      if (error != null && !cancelled && (httpStatus ?? 0) >= 300)
        "http_status": httpStatus,
    });
  }
}

/// An error mpv reported on its error stream while loading. Only its type
/// goes into telemetry, never mpv's message (it can hold the URL).
class MediaPlayerLoadError implements Exception {
  const MediaPlayerLoadError();
}

/// Vommet issue 1065: media_kit's `Player.open` only hands mpv the file
/// (media_kit 1.2.6 NativePlayer.open sends `loadfile` and returns), so it
/// says nothing about whether the file loads. This ends [watch] on the
/// player's first real signal instead: a duration, a video size or buffered
/// data means ok, the error stream means error, [cancel] (dispose) before
/// either means cancelled. The watch's stall timer runs until then.
class PlayerLoadWatch {
  PlayerLoadWatch(this.watch, Player player) {
    _subs = [
      player.stream.duration.listen((d) {
        if (d > Duration.zero) _end();
      }),
      player.stream.width.listen((w) {
        if ((w ?? 0) > 0) _end();
      }),
      player.stream.buffer.listen((b) {
        if (b > Duration.zero) _end();
      }),
      player.stream.error.listen((_) {
        _end(error: const MediaPlayerLoadError());
      }),
    ];
  }

  final MediaLoadWatch watch;
  late final List<StreamSubscription> _subs;

  /// `open` itself threw.
  void fail(Object error) => _end(error: error);

  /// The player went away before the file loaded.
  void cancel() => _end(cancelled: true);

  void _end({Object? error, bool cancelled = false}) {
    for (final s in _subs) {
      s.cancel();
    }
    watch.end(error: error, cancelled: cancelled);
  }
}
