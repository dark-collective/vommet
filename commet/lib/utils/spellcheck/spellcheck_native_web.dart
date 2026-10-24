import 'dart:typed_data';

/// Vommet: web stand-in for spellcheck_native.dart, which loads the Rust
/// library through dart:ffi (not available on web). [Spellcheck.supported]
/// is false on web, so none of this is called.
class SpellcheckNative {
  SpellcheckNative._();

  static SpellcheckNative? get instance => null;

  static Future<SpellcheckNative> load() =>
      Future.error(UnsupportedError("Spellcheck isn't available on web"));

  int open(Uint8List aff, Uint8List dic) => 0;

  int check(int dictionary, String word) => 1;

  List<String> suggest(int dictionary, String word, int max) => const [];

  void close(int dictionary) {}

  static Future<int> openFiles(String affPath, String dicPath) =>
      Future.error(UnsupportedError("Spellcheck isn't available on web"));

  static Future<List<List<String>>> suggestIn(
          List<int> dictionaries, String word, int max) =>
      Future.value([for (final _ in dictionaries) const <String>[]]);
}
