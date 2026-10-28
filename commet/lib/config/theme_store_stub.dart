import 'dart:typed_data';

/// Custom themes kept in the browser, by theme name. Web only: everywhere
/// else they are folders under the app support directory.
class WebThemeStore {
  static Future<List<String>> names() => throw UnsupportedError("web only");

  static Future<Map<String, Uint8List>> files(String name) =>
      throw UnsupportedError("web only");

  static Future<void> put(String name, Map<String, Uint8List> files) =>
      throw UnsupportedError("web only");

  static Future<void> remove(String name) => throw UnsupportedError("web only");
}
