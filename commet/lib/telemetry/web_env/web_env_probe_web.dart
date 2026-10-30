// Vommet: reads the browser environment for the `web_env` event. The user
// agent is only parsed on the device (web_env_telemetry.dart); it is never
// sent.
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

@JS("WebAssembly.validate")
external bool _wasmValidate(JSUint8Array bytes);

class WebEnvProbe {
  final bool wasm;
  final String vendor;
  final String userAgent;
  final bool crossOriginIsolated;
  final int webgl;
  final bool supportsWasmGC;

  const WebEnvProbe({
    required this.wasm,
    required this.vendor,
    required this.userAgent,
    required this.crossOriginIsolated,
    required this.webgl,
    required this.supportsWasmGC,
  });

  static WebEnvProbe? read() {
    return WebEnvProbe(
      wasm: const bool.fromEnvironment("dart.tool.dart2wasm"),
      vendor: web.window.navigator.vendor,
      userAgent: web.window.navigator.userAgent,
      crossOriginIsolated: web.window.crossOriginIsolated,
      webgl: _webglVersion(),
      supportsWasmGC: _supportsWasmGC(),
    );
  }

  static int _webglVersion() {
    try {
      final canvas = web.HTMLCanvasElement()
        ..width = 1
        ..height = 1;
      if (canvas.getContext("webgl2") != null) return 2;
      if (canvas.getContext("webgl") != null) return 1;
    } catch (_) {}
    return 0;
  }

  // The same module Flutter's loader validates: it is only valid where the
  // final WasmGC spec is implemented.
  static bool _supportsWasmGC() {
    try {
      final bytes = Uint8List.fromList(
          [0, 97, 115, 109, 1, 0, 0, 0, 1, 5, 1, 95, 1, 120, 0]);
      return _wasmValidate(bytes.toJS);
    } catch (_) {
      return false;
    }
  }
}
