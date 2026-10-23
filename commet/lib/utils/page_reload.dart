// Vommet issue 593: the web app's new-version bar reloads the page (a no-op
// elsewhere).
export 'page_reload_stub.dart'
    if (dart.library.js_interop) 'page_reload_web.dart';
