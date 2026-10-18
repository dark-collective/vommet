// Vommet: a recovery key copied for a password manager comes off the
// clipboard again once the screen that copied it is done with it, so it
// doesn't linger in clipboard history or for other apps to read.
import 'package:flutter/services.dart';

class RecoveryKeyClipboard {
  /// Empties the clipboard if it still holds [key]. Anything the user
  /// copied since stays.
  static Future<void> clearIfHolds(String? key) async {
    final want = key?.trim();
    if (want == null || want.isEmpty) return;
    try {
      final clip = await Clipboard.getData(Clipboard.kTextPlain);
      if (clip?.text?.trim() == want) {
        await Clipboard.setData(const ClipboardData(text: ""));
      }
    } catch (_) {
      // No clipboard on this platform, or it's busy: nothing to clear.
    }
  }
}
