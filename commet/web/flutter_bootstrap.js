{{flutter_js}}
{{flutter_build_config}}

// Vommet: loads the WebAssembly build (skwasm renderer) where the browser has
// WasmGC, else the JS build (CanvasKit); `flutter build web --wasm` builds
// both. Everything comes from this site: CanvasKit/skwasm via
// --no-web-resources-cdn, the fallback fonts from fonts/fallback/
// (.vommet/web/fonts.sh), so nothing is fetched from Google.
(function () {
  // Without WebGL the engine's software fallback freezes the page
  // (index.html says what's needed instead).
  if (!hasWebGL()) {
    showNoWebGL();
    return;
  }
  _flutter.loader.load({
    config: {
      fontFallbackBaseUrl: "fonts/fallback/",
    },
  });
})();
