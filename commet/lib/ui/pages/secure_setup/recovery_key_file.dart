import 'package:commet/client/matrix/key_export/megolm_key_file.dart';
import 'package:commet/ui/pages/secure_setup/secure_setup_controller.dart';

enum RecoveryKeyFileKind {
  /// A recovery key was found ([RecoveryKeyFileResult.key]).
  key,

  /// A key export (Megolm session data): a backup of message keys, which
  /// can't answer a recovery key check.
  keyExport,

  /// Nothing shaped like a recovery key.
  none
}

typedef RecoveryKeyFileResult = ({RecoveryKeyFileKind kind, String? key});

/// A recovery key saved as a file: Element's recovery-key.txt (the key in
/// groups of 4, "EsTc 2JiT …", maybe with a line break or some text
/// around it), or a text file the user saved it in.
class RecoveryKeyFile {
  /// The recovery key in [text]. A key that passes its own checks (prefix,
  /// length, parity) wins; failing that, the first look-alike, so a typo
  /// is reported as a wrong key rather than as "no key in that file".
  static RecoveryKeyFileResult parse(String text) {
    if (MegolmKeyFile.looksLikeKeyFile(text)) {
      return (kind: RecoveryKeyFileKind.keyExport, key: null);
    }
    final words = text
        .split(RegExp(r"\s+"))
        .map((w) => w.trim())
        .where((w) => w.isNotEmpty)
        .toList();
    String? lookAlike;
    for (var i = 0; i < words.length; i++) {
      if (!words[i].startsWith("E")) continue;
      var joined = "";
      for (var j = i; j < words.length; j++) {
        final w = words[j];
        if (!RegExp(r"^[0-9A-Za-z]+$").hasMatch(w)) break;
        joined += w;
        if (joined.length > 52) break;
        if (!SecureSetupController.looksLikeRecoveryKey(joined)) continue;
        if (SecureSetupController.isValidRecoveryKey(joined)) {
          return (kind: RecoveryKeyFileKind.key, key: _grouped(joined));
        }
        lookAlike ??= joined;
      }
    }
    if (lookAlike != null) {
      return (kind: RecoveryKeyFileKind.key, key: _grouped(lookAlike));
    }
    return (kind: RecoveryKeyFileKind.none, key: null);
  }

  /// In groups of 4, as recovery keys are shown.
  static String _grouped(String compact) => [
        for (var i = 0; i < compact.length; i += 4)
          compact.substring(i, (i + 4).clamp(0, compact.length))
      ].join(" ");
}
