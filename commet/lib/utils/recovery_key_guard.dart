// Vommet: spots a Matrix recovery key in text about to be sent, so people
// don't paste theirs into a chat. Uses the SDK's own decoder (prefix, length
// and parity), so ordinary text that merely looks similar never triggers it.
import 'package:matrix/encryption.dart';

class RecoveryKeyGuard {
  static final _whitespace = RegExp(r'\s+');
  static final _base58 = RegExp(r'^[1-9A-HJ-NP-Za-km-z]+$');

  static bool containsRecoveryKey(String text) {
    final tokens = text
        .split(_whitespace)
        .where((t) => t.isNotEmpty && _base58.hasMatch(t))
        .toList();

    // A key is usually written in groups of 4, but may be pasted as one
    // block: try every run of consecutive tokens that adds up to key length.
    for (var start = 0; start < tokens.length; start++) {
      var joined = "";
      for (var end = start; end < tokens.length; end++) {
        joined += tokens[end];
        if (joined.length > 52) break;
        if (joined.length >= 44 && _decodes(joined)) return true;
      }
    }
    return false;
  }

  static bool _decodes(String candidate) {
    try {
      SSSS.decodeRecoveryKey(candidate);
      return true;
    } catch (_) {
      return false;
    }
  }
}
