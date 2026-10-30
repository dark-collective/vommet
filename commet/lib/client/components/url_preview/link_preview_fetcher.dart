// Vommet issue 676 phase 2: this device fetches a page to attach its
// preview to a message. Native apps only: a browser can't read other
// sites' pages (CORS), and a proxy would see every link.
export 'package:commet/client/components/url_preview/link_preview_fetcher_stub.dart'
    if (dart.library.io) 'package:commet/client/components/url_preview/link_preview_fetcher_io.dart';
