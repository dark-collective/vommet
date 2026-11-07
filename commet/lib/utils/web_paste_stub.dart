import 'dart:typed_data';

/// Vommet: no DOM here; pictures come from the pasteboard plugin instead.
class WebPaste {
  /// Returns a function that stops listening.
  static void Function() listenForImages(
      void Function(Uint8List data) onImage) {
    return () {};
  }
}
