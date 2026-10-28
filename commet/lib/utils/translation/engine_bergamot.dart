import 'dart:io';

import 'package:bergamot_translator/bergamot_translator.dart';
import 'package:commet/utils/translation/engine.dart';
import 'package:commet/utils/translation/engine_stub.dart';
import 'package:flutter/foundation.dart';

TranslationEngine createEngine() =>
    (Platform.isLinux || Platform.isAndroid || Platform.isWindows)
        ? BergamotTranslationEngine()
        : UnavailableTranslationEngine();

class BergamotTranslationEngine implements TranslationEngine {
  bool? _available;
  String? _reason;
  final Set<String> _loaded = {};

  @override
  bool get available => _available ??= _probe();

  @override
  String? get unavailableReason {
    available;
    return _reason;
  }

  bool _probe() {
    final cpu = _cpuProblem();
    if (cpu != null) {
      _reason = cpu;
      return false;
    }
    try {
      // Opens the library; CLD2 needs no model.
      BergamotTranslator.detectLanguage("Hello, how are you today?");
      return true;
    } catch (e) {
      debugPrint("Translation engine unavailable: $e");
      _reason = Platform.isAndroid
          ? "Translation needs Android 9 or later."
          : "The translation engine couldn't be loaded.";
      return false;
    }
  }

  /// The Linux x86_64 library is built for x86-64-v2 (SSE4.2, 2009+).
  static String? _cpuProblem() {
    if (!Platform.isLinux) return null;
    try {
      final info = File("/proc/cpuinfo").readAsStringSync();
      final flags = RegExp(r"^flags\s*:(.*)$", multiLine: true)
          .firstMatch(info)
          ?.group(1)
          ?.split(" ")
          .toSet();
      if (flags == null) return null; // not x86 (aarch64 says "Features")
      const needed = ["ssse3", "sse4_1", "sse4_2", "popcnt"];
      if (needed.every(flags.contains)) return null;
      return "This computer's processor can't run translation (it needs SSE4.2).";
    } catch (_) {
      return null;
    }
  }

  @override
  DetectedLanguage? detect(String text) {
    if (!available) return null;
    try {
      final r = BergamotTranslator.detectLanguage(text);
      return DetectedLanguage(r.language,
          reliable: r.isReliable, confidence: r.confidence);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> load(String key, String config) async {
    if (_loaded.contains(key)) return;
    await BergamotTranslator.loadModelAsync(config, key);
    _loaded.add(key);
  }

  @override
  Future<List<String>> translate(List<String> lines, List<String> keys) {
    if (keys.length == 1) {
      return BergamotTranslator.translateMultipleAsync(lines, keys.single);
    }
    return BergamotTranslator.pivotMultipleAsync(lines, keys[0], keys[1]);
  }

  @override
  Future<void> unloadAll() async {
    if (_loaded.isEmpty) return;
    await BergamotTranslator.cleanupAsync(false);
    _loaded.clear();
  }
}
