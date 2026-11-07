// Why the previous run ended (Android). Native and Java crashes kill the
// process before Dart can record them, so on the next launch we ask the
// platform (ExitInfo.kt): Android's exit reason (11+), plus the class name
// and stack frames our uncaught-exception handler saved. Never messages.

import 'package:commet/config/platform_utils.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/telemetry/telemetry.dart';
import 'package:flutter/services.dart';

class ExitTelemetry {
  static const _channel = MethodChannel("im.nether.chat/exit_info");
  static bool _checked = false;
  static final _javaType = RegExp(r"^[A-Za-z_$][A-Za-z0-9_$.]{0,159}$");
  static final _javaFrame =
      RegExp(r"^[A-Za-z_$][A-Za-z0-9_$.<>-]{0,199}:[0-9]{1,6}$");

  static final _nativeFrame = RegExp(
      r"^[A-Za-z0-9_.+?-]{1,80}(![A-Za-z0-9_$.]{1,200})?\+0x[0-9a-f]{1,16}$");
  static final _thread = RegExp(r"^[A-Za-z0-9_ .:#/-]{1,32}$");

  static String? _type(Object? v) =>
      v is String && _javaType.hasMatch(v) ? v : null;

  static String _importance(int? v) {
    if (v == null) return "other";
    if (v <= 100) return "foreground";
    if (v <= 125) return "foreground_service";
    if (v <= 200) return "visible";
    if (v <= 230) return "perceptible";
    if (v <= 300) return "service";
    if (v <= 400) return "cached";
    if (v >= 1000) return "gone";
    return "other";
  }

  static Future<void> reportPreviousExit() async {
    if (_checked || !PlatformUtils.isAndroid) return;
    _checked = true;
    try {
      final info = await _channel.invokeMapMethod<String, Object?>("lastExit");
      if (info == null) return;
      final ageMs = info["age_ms"] as int?;
      Telemetry.record("exit_reason", {
        "reason": info["reason"] ?? "unknown",
        "status": info["status"],
        "importance": info.containsKey("importance")
            ? _importance(info["importance"] as int?)
            : null,
        "age": ageMs == null ? null : (ageMs ~/ 1000).clamp(0, 2592000),
        "java_error_type": _type(info["java_error_type"]),
        "java_outer_type": _type(info["java_outer_type"]),
        "java_frames": (info["java_frames"] as List?)
            ?.whereType<String>()
            .where(_javaFrame.hasMatch)
            .take(25)
            .toList(),
        "native_frames": (info["native_frames"] as List?)
            ?.whereType<String>()
            .where(_nativeFrame.hasMatch)
            .take(30)
            .toList(),
        "native_thread": info["native_thread"] is String &&
                _thread.hasMatch(info["native_thread"] as String)
            ? info["native_thread"]
            : null,
        "abort_kind": info["abort_kind"],
      });
    } catch (e, s) {
      Log.onError(e, s, content: "Could not read the previous exit reason");
    }
  }
}
