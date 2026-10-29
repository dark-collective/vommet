// Vommet issue 767: the browser's Notification API for the web app (a stub
// everywhere else).
export 'browser_notifications_stub.dart'
    if (dart.library.js_interop) 'browser_notifications_web.dart';
