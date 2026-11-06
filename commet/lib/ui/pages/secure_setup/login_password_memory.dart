import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Vommet issue 129: remembers, in memory only, a salted hash of the
/// password the user just signed in with, so the "own recovery password"
/// screen can warn when it's the same. Never written anywhere; cleared once
/// setup is done. Only exists after a password sign-in in this run (not
/// after SSO, not on a later launch).
class LoginPasswordMemory {
  static final Map<String, (List<int>, Digest)> _byAccount = {};

  static void remember(String accountKey, String password) {
    final rng = Random.secure();
    final salt = List<int>.generate(16, (_) => rng.nextInt(256));
    _byAccount[accountKey] = (salt, _hash(salt, password));
  }

  /// True/false when known, null when we can't tell.
  static bool? isLoginPassword(String accountKey, String candidate) {
    final entry = _byAccount[accountKey];
    if (entry == null) return null;
    return _hash(entry.$1, candidate) == entry.$2;
  }

  static void forget(String accountKey) => _byAccount.remove(accountKey);

  static Digest _hash(List<int> salt, String password) =>
      sha256.convert([...salt, ...utf8.encode(password)]);
}
