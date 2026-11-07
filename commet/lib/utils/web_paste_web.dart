import 'dart:js_interop';
import 'dart:typed_data';

import 'package:commet/debug/log.dart';
import 'package:web/web.dart' as web;

/// Vommet: pictures pasted into the page (Ctrl+V, the browser's Paste menu).
/// Browsers give them to the `paste` event only, as files on the
/// clipboardData; text pastes are left alone for the text field.
class WebPaste {
  /// Calls [onImage] with each picture pasted anywhere on the page. Returns a
  /// function that stops listening.
  static void Function() listenForImages(
      void Function(Uint8List data) onImage) {
    final listener = (web.Event event) {
      final files = (event as web.ClipboardEvent).clipboardData?.files;
      if (files == null) return;

      for (var i = 0; i < files.length; i++) {
        final file = files.item(i);
        if (file == null || !file.type.startsWith("image/")) continue;

        event.preventDefault();
        file.arrayBuffer().toDart.then((buffer) {
          onImage(buffer.toDart.asUint8List());
        }, onError: (Object e) => Log.w("Reading the pasted image failed: $e"));
      }
    }.toJS;

    web.document.addEventListener("paste", listener);
    return () => web.document.removeEventListener("paste", listener);
  }
}
