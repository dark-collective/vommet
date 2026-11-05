import 'package:commet/utils/translation/engine_stub.dart'
    if (dart.library.ffi) 'package:commet/utils/translation/engine_bergamot.dart'
    as impl;

/// A language guess for a piece of text, in Firefox Translations' codes.
class DetectedLanguage {
  const DetectedLanguage(this.code,
      {required this.reliable, required this.confidence});

  final String code;
  final bool reliable;

  /// 0..100
  final int confidence;
}

/// The on-device translation engine (Bergamot, through the vendored
/// bergamot_translator plugin). Tests use a fake.
abstract class TranslationEngine {
  static TranslationEngine create() => impl.createEngine();

  /// Whether the native library is there and this CPU can run it. Only the
  /// Linux, Windows and Android builds bundle it; Android needs 9 or later.
  bool get available;

  /// Why [available] is false, for the settings page.
  String? get unavailableReason;

  /// Guesses the language of [text] (CLD2: no model needed, fast enough to
  /// run while a message is built). Null when it can't tell.
  DetectedLanguage? detect(String text);

  /// Loads a model under [key] from its Marian [config]. Loading the same
  /// key twice is a no-op.
  Future<void> load(String key, String config);

  /// Translates each of [lines] through the models [keys] (one, or two to go
  /// through English).
  Future<List<String>> translate(List<String> lines, List<String> keys);

  /// Frees every loaded model (before deleting model files).
  Future<void> unloadAll();
}
