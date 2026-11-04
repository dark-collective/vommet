// Vommet: how much of each shipped language is translated, for the
// Settings › General › Language list. Counted at runtime from the bundled
// arb files (assets/l10n/ is already an asset directory), so it needs no
// codegen step and always matches the translations in the build.
import 'dart:convert';

import 'package:commet/config/app_language.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class TranslationProgress {
  static Future<Map<String, int>>? _loading;

  /// Percent translated per language id (English is 100). Loaded once.
  static Future<Map<String, int>> load() => _loading ??= _load();

  static Future<Map<String, int>> _load() async {
    final sources = <String, String>{};
    for (final l in AppLanguages.all) {
      try {
        sources[l.id] =
            await rootBundle.loadString("assets/l10n/intl_${l.messages}.arb");
      } catch (_) {
        // A missing file counts as not translated.
      }
    }
    return compute(percentages, sources);
  }

  /// [arbSources] maps language id → arb file contents. A key counts as
  /// translated when the language's arb has a non-empty string for a
  /// message key of the English arb. Rounded down, but never to 0% when
  /// something is translated, and English is always 100.
  static Map<String, int> percentages(Map<String, String> arbSources,
      {String reference = AppLanguages.english}) {
    Set<String> translatedKeys(String source) {
      final Object? data;
      try {
        data = jsonDecode(source);
      } catch (_) {
        return const {};
      }
      if (data is! Map) return const {};
      return {
        for (final e in data.entries)
          if (e.key is String &&
              !(e.key as String).startsWith("@") &&
              e.value is String &&
              (e.value as String).trim().isNotEmpty)
            e.key as String,
      };
    }

    final referenceKeys = translatedKeys(arbSources[reference] ?? "{}");
    final result = <String, int>{};
    for (final e in arbSources.entries) {
      if (e.key == reference || referenceKeys.isEmpty) {
        result[e.key] = e.key == reference ? 100 : 0;
        continue;
      }
      final done = translatedKeys(e.value).intersection(referenceKeys).length;
      var pct = done * 100 ~/ referenceKeys.length;
      if (pct == 0 && done > 0) pct = 1;
      result[e.key] = pct;
    }
    result[reference] = 100;
    return result;
  }
}
