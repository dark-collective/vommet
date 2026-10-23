// Vommet: one `web_env` event per session on the web build, so diagnostics
// show which compiled build runs (WebAssembly or JS), in which browser engine
// family and major version, and why the JS fallback was picked. Only those
// fixed values: never the user agent string, OS, screen or GPU name.

import 'package:commet/telemetry/web_env/web_env_probe.dart'
    if (dart.library.js_interop) 'package:commet/telemetry/web_env/web_env_probe_web.dart';

class WebEnvTelemetry {
  /// The `web_env` fields, or null when not running in a browser.
  static Map<String, Object?>? fields() {
    final probe = WebEnvProbe.read();
    if (probe == null) return null;
    final engine = engineFamily(probe.vendor, probe.userAgent);
    return {
      "build": probe.wasm ? "wasm" : "js",
      "engine": engine,
      "engine_major": engineMajor(engine, probe.userAgent),
      "cross_origin_isolated": probe.crossOriginIsolated,
      "webgl": probe.webgl.clamp(0, 2),
      "fallback_reason": fallbackReason(
          wasm: probe.wasm, supportsWasmGC: probe.supportsWasmGC),
    };
  }

  /// The browser engine the way Flutter's loader decides it
  /// (flutter_js browser_environment.js), so it matches its wasmAllowList.
  static String engineFamily(String vendor, String userAgent) {
    if (vendor == "Google Inc." || userAgent.contains("Edg/")) return "blink";
    if (vendor == "Apple Computer, Inc.") return "webkit";
    if (vendor == "" && userAgent.contains("Firefox")) return "gecko";
    return "other";
  }

  /// The browser's major version for [engine], or null when it can't be
  /// read. Only the number leaves the device.
  static int? engineMajor(String engine, String userAgent) {
    final pattern = switch (engine) {
      "blink" => RegExp(r"(?:Chrome|Chromium|CriOS)/(\d{1,4})"),
      "gecko" => RegExp(r"Firefox/(\d{1,4})"),
      "webkit" => RegExp(r"Version/(\d{1,4})"),
      _ => null,
    };
    final match = pattern?.firstMatch(userAgent);
    if (match == null) return null;
    final major = int.tryParse(match.group(1)!);
    if (major == null || major > 1000) return null;
    return major;
  }

  /// Why the JS build runs: the browser lacks WasmGC, or it has WasmGC but
  /// its engine isn't in the loader's wasmAllowList. "none" on WebAssembly.
  static String fallbackReason(
      {required bool wasm, required bool supportsWasmGC}) {
    if (wasm) return "none";
    return supportsWasmGC ? "allowlist" : "no_wasmgc";
  }
}
