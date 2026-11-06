// Vommet: free disk space and directory fsync go through dart:ffi, which
// doesn't exist on web; the web build gets a stub (no local data encryption
// there).
export 'disk_space_native.dart'
    if (dart.library.js_interop) 'disk_space_web.dart';
