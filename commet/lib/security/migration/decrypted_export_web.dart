// Vommet: web stand-in for decrypted_export_native.dart. The web app has no
// local data encryption, so there is nothing to export.
import 'dart:typed_data';

import 'package:commet/security/key_vault/key_vault.dart';

class DecryptedExportError implements Exception {
  const DecryptedExportError(this.message);
  final String message;

  @override
  String toString() => "DecryptedExportError: $message";
}

class DecryptedExport {
  static const _unsupported =
      DecryptedExportError("not supported in the web app");

  static void exportSync(String source, Uint8List? key, String target) =>
      throw _unsupported;

  static Future<void> export(String source, Uint8List? key, String target) =>
      Future.error(_unsupported);

  static Future<List<String>> exportAll({
    required KeyVault vault,
    required String databaseDirectory,
    required List<String> accounts,
    required String folder,
  }) async =>
      const ["Export decrypted copy is not supported in the web app."];
}
