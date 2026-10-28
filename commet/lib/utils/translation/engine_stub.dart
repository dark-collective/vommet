import 'package:commet/utils/translation/engine.dart';

TranslationEngine createEngine() => UnavailableTranslationEngine();

/// Web: no native code.
class UnavailableTranslationEngine implements TranslationEngine {
  @override
  bool get available => false;

  @override
  String? get unavailableReason => "Translation isn't available here yet.";

  @override
  DetectedLanguage? detect(String text) => null;

  @override
  Future<void> load(String key, String config) =>
      Future.error(UnsupportedError("no translation engine"));

  @override
  Future<List<String>> translate(List<String> lines, List<String> keys) =>
      Future.error(UnsupportedError("no translation engine"));

  @override
  Future<void> unloadAll() async {}
}
