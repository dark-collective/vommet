// Vommet: browsers only hand out pasted pictures through the DOM paste event
// (the pasteboard plugin has no web support); other platforms get a stub.
export 'web_paste_stub.dart' if (dart.library.js_interop) 'web_paste_web.dart';
