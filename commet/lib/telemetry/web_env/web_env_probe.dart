// Vommet: native builds have no browser environment (see web_env_probe_web.dart).

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

  static WebEnvProbe? read() => null;
}
