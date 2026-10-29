// Vommet: owner-only permissions go through dart:ffi (libc chmod), which
// doesn't exist on web; the web build gets a stub (it has no files).
export 'owner_only_native.dart'
    if (dart.library.js_interop) 'owner_only_web.dart';
