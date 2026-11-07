// Vommet: widgets in the web app open in an <iframe> on the page; other
// platforms have their own runners and get a stub.
export 'matrix_widget_web_frame_stub.dart'
    if (dart.library.js_interop) 'matrix_widget_web_frame_web.dart';
