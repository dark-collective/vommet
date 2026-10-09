/// Vommet issue 129: a rough strength meter for an own recovery password.
/// Not a cracking estimate; it nudges people toward long passphrases. Score
/// 0 (too easy) to 4 (strong).
class PasswordStrength {
  static const labels = [
    "Too easy to guess",
    "Weak",
    "Okay",
    "Good",
    "Strong",
  ];

  static const _common = {
    "password",
    "passw0rd",
    "123456",
    "12345678",
    "123456789",
    "qwerty",
    "letmein",
    "iloveyou",
    "admin",
    "welcome",
    "monkey",
    "dragon",
    "football",
    "baseball",
    "sunshine",
    "princess",
    "abc123",
    "111111",
    "matrix",
    "element",
    "vommet",
    "commet",
    "secret",
    "recovery",
  };

  static int score(String password) {
    final p = password.trim();
    if (p.length < 8) return 0;
    final lower = p.toLowerCase();
    if (_common.any((c) => lower.contains(c)) && p.length < 16) return 0;
    if (RegExp(r"^(.)\1+$").hasMatch(p)) return 0;
    if (RegExp(r"^\d+$").hasMatch(p) && p.length < 16) return 0;

    var classes = 0;
    if (RegExp(r"[a-z]").hasMatch(p)) classes++;
    if (RegExp(r"[A-Z]").hasMatch(p)) classes++;
    if (RegExp(r"\d").hasMatch(p)) classes++;
    if (RegExp(r"[^A-Za-z0-9]").hasMatch(p)) classes++;
    final words = p.split(RegExp(r"\s+")).where((w) => w.length >= 3).length;

    if (p.length >= 20 || words >= 4) return 4;
    if (p.length >= 16 || (p.length >= 12 && classes >= 3)) return 3;
    if (p.length >= 12 || classes >= 3) return 2;
    return 1;
  }

  /// Strong enough to save: "Good" or better. The salt sits on the server,
  /// so a weak one could be guessed offline by whoever runs it.
  static bool acceptable(String password) => score(password) >= 3;
}
