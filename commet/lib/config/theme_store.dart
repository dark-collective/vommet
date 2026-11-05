// Vommet: custom themes on web live in the browser's IndexedDB (there is no
// app support folder there); other platforms keep them as files.
export 'theme_store_stub.dart'
    if (dart.library.js_interop) 'theme_store_web.dart';
