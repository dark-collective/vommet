import 'dart:async';

import 'package:commet/config/platform_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Vommet issue 936: Convert to GIF's frames from Android's own decoder
/// (VommetVideoFrames.kt), which goes through the clip once instead of
/// seeking the player for every frame. Everything stays in memory.
class VideoFramesAndroid {
  static const _channel = MethodChannel("im.nether.chat/video_frames");

  /// Only for a file on the device; the player handles the rest.
  static bool canUse(String? path) =>
      !kIsWeb && PlatformUtils.isAndroid && path != null && path.isNotEmpty;

  static int _nextId = 0;
  static final Map<int, void Function(int index, Uint8List rgb)> _jobs = {};
  static bool _listening = false;

  static void _listen() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != "frame") return;
      final args = call.arguments as Map;
      _jobs[args["id"] as int]?.call(args["index"] as int, args["rgb"]);
    });
  }

  /// [count] small JPEGs spread along the video (from its key frames, so
  /// this is quick); null for one that couldn't be made.
  static Future<List<Uint8List?>> thumbnails(String path,
      {required int count, int edge = 96}) async {
    final shots = await _channel.invokeListMethod<Uint8List?>(
        "thumbnails", {"source": path, "count": count, "edge": edge});
    return shots ?? [];
  }

  /// Packed RGB frames at [times] (ascending), the longest side at most
  /// [edge] px. [onFrame] is told as each one arrives. Fewer frames than
  /// [times] when the video ends first. Throws when the video can't be
  /// decoded this way, or when [canceled] turns true.
  static Future<(int, int, List<Uint8List>)> frames(
    String path,
    List<Duration> times, {
    required int edge,
    void Function(int done)? onFrame,
    bool Function()? canceled,
  }) async {
    _listen();
    final id = _nextId++;
    final frames = <Uint8List>[];
    _jobs[id] = (index, rgb) {
      if (index != frames.length) return;
      frames.add(rgb);
      onFrame?.call(frames.length);
    };
    var stopped = false;
    final watch = canceled == null
        ? null
        : Timer.periodic(const Duration(milliseconds: 100), (_) {
            if (!stopped && canceled()) {
              stopped = true;
              _channel.invokeMethod("cancel", {"id": id});
            }
          });
    try {
      final size = await _channel.invokeMapMethod<String, int>("frames", {
        "id": id,
        "source": path,
        "timesUs": [for (final t in times) t.inMicroseconds],
        "edge": edge,
      });
      if (canceled?.call() ?? false) throw StateError("canceled");
      final width = size?["width"] ?? 0, height = size?["height"] ?? 0;
      if (width <= 0 || height <= 0 || frames.isEmpty) {
        throw StateError("no frames");
      }
      for (final f in frames) {
        if (f.length != width * height * 3) throw StateError("bad frame");
      }
      return (width, height, frames);
    } finally {
      watch?.cancel();
      _jobs.remove(id);
    }
  }
}
