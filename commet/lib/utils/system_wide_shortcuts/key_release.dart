// Vommet: key release polling goes through dart:ffi (Win32 / X11), which
// doesn't exist on web; the web build gets a stub that can't tell releases.
export 'key_release_native.dart'
    if (dart.library.js_interop) 'key_release_web.dart';
