// Vommet: mpv properties exist only on media_kit's native player; the web
// build's NativePlayer stub has no setProperty.
export 'mpv_property_native.dart'
    if (dart.library.js_interop) 'mpv_property_web.dart';
