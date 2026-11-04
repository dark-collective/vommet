import 'dart:math';

import 'package:flutter/services.dart';

/// Vommet issue 129: the 6-word recovery phrase. Words come from the EFF
/// large wordlist (7776 words, see assets/data/sources.txt), picked with a
/// secure random generator: 6 words ≈ 77.5 bits, used as the secret storage
/// passphrase (the SDK stretches it with PBKDF2).
class RecoveryPhrase {
  RecoveryPhrase(this.words);

  static const length = 6;
  static List<String>? _wordlist;

  final List<String> words;

  /// As stored: lower case, single spaces.
  String get passphrase => words.join(" ");

  static Future<List<String>> wordlist() async => _wordlist ??=
      (await rootBundle.loadString("assets/data/eff_large_wordlist.txt"))
          .split("\n")
          .map((w) => w.trim())
          .where((w) => w.isNotEmpty)
          .toList(growable: false);

  static Future<RecoveryPhrase> generate({Random? random}) async =>
      fromList(await wordlist(), random: random);

  static RecoveryPhrase fromList(List<String> list, {Random? random}) {
    final rng = random ?? Random.secure();
    return RecoveryPhrase(
        [for (var i = 0; i < length; i++) list[rng.nextInt(list.length)]]);
  }

  /// Two different positions (0-based) to ask for in the confirm step.
  static (int, int) confirmPositions({Random? random}) {
    final rng = random ?? Random.secure();
    final a = rng.nextInt(length);
    var b = rng.nextInt(length - 1);
    if (b >= a) b++;
    return a < b ? (a, b) : (b, a);
  }

  /// Did the user type the word at [position]? Ignores case and spaces.
  bool matches(int position, String typed) =>
      typed.trim().toLowerCase() == words[position];
}
