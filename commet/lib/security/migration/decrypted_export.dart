// Vommet: "Export decrypted copy" opens databases with package:sqlite3
// (dart:ffi), which doesn't exist on web; the web build gets a stub that
// reports the export as not supported.
export 'decrypted_export_native.dart'
    if (dart.library.js_interop) 'decrypted_export_web.dart';
