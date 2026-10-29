import 'dart:convert';

import 'package:commet/utils/translation/engine.dart';
import 'package:commet/utils/translation/model_spec.dart';
import 'package:crypto/crypto.dart';

// Shared by the translation tests (Vommet issue 680).

/// Detects by a "[xx]" prefix; translates by tagging each line with the keys.
class FakeEngine implements TranslationEngine {
  final loaded = <String, String>{};
  final calls = <List<String>>[];

  @override
  bool get available => true;

  @override
  String? get unavailableReason => null;

  @override
  DetectedLanguage? detect(String text) {
    final m = RegExp(r"^\[([a-zA-Z-]+)\]").firstMatch(text);
    if (m == null) return null;
    return DetectedLanguage(m.group(1)!,
        reliable: !text.contains("unsure"), confidence: 90);
  }

  @override
  Future<void> load(String key, String config) async => loaded[key] = config;

  @override
  Future<List<String>> translate(List<String> lines, List<String> keys) async {
    calls.add(keys);
    return [for (final l in lines) "${keys.join("+")}: $l"];
  }

  @override
  Future<void> unloadAll() async => loaded.clear();
}

/// A tiny model whose three files serve from [blobs].
TranslationModelSpec spec(String from, String to, Map<String, List<int>> blobs,
    {ModelPlatforms platforms = ModelPlatforms.all}) {
  F file(F Function(String, String, int, String) make, String name) {
    final blob = "$from$to-$name";
    final data = utf8.encode("$from-$to $name");
    blobs[blob] = data;
    return make(name, blob, data.length, sha256.convert(data).toString());
  }

  return TranslationModelSpec(from, to, "1.0", platforms, [
    file(F.model, "model.$from$to.bin"),
    file(F.lex, "lex.$from$to.bin"),
    file(F.vocab, "vocab.$from$to.spm"),
  ]);
}
