import 'dart:ui_web' as ui_web;

import 'package:flutter/foundation.dart' show kIsWasm;

/// Vommet: whether the engine's image decoding crops instead of resizing
/// when given a target size. Skwasm (the WebAssembly build) decodes through
/// an <img> element wherever the browser has no ImageDecoder it trusts, i.e.
/// outside Blink (Firefox, Safari), and passes the target size to
/// createImageBitmap as a crop rectangle, upscaling targets included (Flutter
/// 3.47.7). A 90 px avatar thumbnail decoded for 128 px came out as a
/// 90x128 cut-out and showed as a black square. CanvasKit (the JS build) and
/// Chromium's ImageDecoder path resize properly.
final bool engineCropsTargetSize =
    kIsWasm && ui_web.browser.browserEngine != ui_web.BrowserEngine.blink;
